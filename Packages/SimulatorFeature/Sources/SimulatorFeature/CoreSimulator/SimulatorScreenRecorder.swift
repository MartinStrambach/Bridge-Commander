import AppKit
import Foundation
import os
import ProcessExecution

/// A finished screen recording.
public struct SimulatorRecording: Equatable, Sendable {
	public var url: URL
	public var duration: Duration
	/// Why it ended before anyone stopped it — the time limit, or `simctl` quitting because the
	/// device shut down — or `nil` when it was stopped.
	public var endedEarly: String?

	public init(url: URL, duration: Duration, endedEarly: String? = nil) {
		self.url = url
		self.duration = duration
		self.endedEarly = endedEarly
	}
}

/// Records simulators' screens with `xcrun simctl io <udid> recordVideo`, one recording per device.
///
/// simctl rather than an `AVAssetWriter` fed from the framebuffer `IOSurface`: it is what
/// Simulator.app's File ▸ Record Screen runs, keeps up at the display's frame rate, and writes a
/// finished file when sent SIGINT — the only clean way to stop it ("Recording started" on stderr
/// once it runs; "Wrote video to: …" on stdout after the interrupt). H.264 rather than simctl's
/// default HEVC, so the file plays and uploads anywhere (merge requests, Slack).
///
/// A recording is capped (`defaultLimit`), and every one still running is interrupted when the app
/// quits, so a forgotten one neither grows without end nor outlives the app as an orphan `simctl`.
public final class SimulatorScreenRecorder: @unchecked Sendable {
	public static let shared = SimulatorScreenRecorder()
	public static let defaultLimit: Duration = .seconds(600)

	private final class Active: @unchecked Sendable {
		let process: Process
		let url: URL
		let started: ContinuousClock.Instant
		/// simctl's stdout and stderr together: the readiness line, and the reason when it fails.
		let output = OSAllocatedUnfairLock(initialState: "")
		let limitTask = OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)

		init(process: Process, url: URL) {
			self.process = process
			self.url = url
			started = ContinuousClock.now
		}

		var duration: Duration {
			ContinuousClock.now - started
		}

		/// What simctl said, without its "Note: No display specified…" chatter.
		var message: String {
			output.withLock { $0 }
				.split(separator: "\n")
				.map { $0.trimmingCharacters(in: .whitespaces) }
				.filter { !$0.isEmpty && !$0.hasPrefix("Note:") }
				.joined(separator: " ")
		}
	}

	private struct State {
		var active: [String: Active] = [:]
		/// Recordings that ended on their own, kept for the next `stop` to report.
		var ended: [String: Result<SimulatorRecording, SimulatorError>] = [:]
	}

	private let state = OSAllocatedUnfairLock<State>(uncheckedState: State())
	private let changes = OSAllocatedUnfairLock<[UUID: AsyncStream<Set<String>>.Continuation]>(initialState: [:])

	private init() {
		NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { [weak self] _ in
			self?.interruptAllBeforeQuitting()
		}
	}

	/// The devices being recorded now.
	public var recordingDeviceIds: Set<String> {
		state.withLock { Set($0.active.keys) }
	}

	/// The devices being recorded, now and whenever that changes — for the pane's record button,
	/// which also has to follow recordings Claude starts and stops.
	public func recordingDeviceIdChanges() -> AsyncStream<Set<String>> {
		let (stream, continuation) = AsyncStream<Set<String>>.makeStream(bufferingPolicy: .bufferingNewest(1))
		let id = UUID()
		changes.withLock { $0[id] = continuation }
		continuation.onTermination = { [weak self] _ in
			self?.changes.withLock { $0[id] = nil }
		}
		continuation.yield(recordingDeviceIds)
		return stream
	}

	private func publishChange() {
		let ids = recordingDeviceIds
		for continuation in changes.withLock({ Array($0.values) }) {
			continuation.yield(ids)
		}
	}

	// MARK: - Starting

	/// Starts recording `udid` to `url` and returns once simctl reports the recording running.
	/// `screenID` is the screen the device shows when it is not the main one (`SimulatorDevice.screenID`).
	public func start(
		udid: String,
		deviceName: String,
		screenID: UInt32? = nil,
		to url: URL,
		limit: Duration = defaultLimit
	) async throws -> URL {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
		// An open iPhone Duo is recorded on its inner panel; simctl records the main screen unless
		// told otherwise. The recording stays on the panel it started on through a fold.
		let display = screenID.map { ["--display=\($0)"] } ?? []
		process.arguments = ["simctl", "io", udid, "recordVideo", "--codec=h264"] + display + [url.path(percentEncoded: false)]
		process.environment = EnvironmentHelper.setupEnvironment()
		let active = Active(process: process, url: url)

		let outputPipe = Pipe()
		let errorPipe = Pipe()
		process.standardOutput = outputPipe
		process.standardError = errorPipe
		process.standardInput = FileHandle.nullDevice
		for pipe in [outputPipe, errorPipe] {
			pipe.fileHandleForReading.readabilityHandler = { handle in
				let text = String(decoding: handle.availableData, as: UTF8.self)
				active.output.withLock { $0 += text }
			}
		}
		process.terminationHandler = { [weak self] _ in
			for pipe in [outputPipe, errorPipe] {
				pipe.fileHandleForReading.readabilityHandler = nil
			}
			self?.processExited(udid: udid, active: active)
		}

		try state.withLock { state in
			if let existing = state.active[udid] {
				throw SimulatorError.alreadyRecording(device: deviceName, path: existing.url.path(percentEncoded: false))
			}
			state.active[udid] = active
			state.ended[udid] = nil
		}

		do {
			try process.run()
		}
		catch {
			remove(active, udid: udid)
			throw SimulatorError.recordingFailed(error.localizedDescription)
		}

		// simctl takes a moment to find the display and set up the writer.
		let clock = ContinuousClock()
		let deadline = clock.now + .seconds(10)
		while !active.output.withLock({ $0.contains("Recording started") }) {
			guard process.isRunning else {
				remove(active, udid: udid)
				throw SimulatorError.recordingFailed(active.message.isEmpty ? "simctl quit without recording" : active.message)
			}
			guard clock.now < deadline else {
				remove(active, udid: udid)
				process.terminate()
				throw SimulatorError.recordingFailed("simctl did not start recording within 10 seconds")
			}
			try? await Task.sleep(for: .milliseconds(50))
		}

		active.limitTask.withLock {
			$0 = Task { [weak self] in
				try? await Task.sleep(for: limit)
				guard !Task.isCancelled, let self else {
					return
				}
				let minutes = Int(limit.components.seconds / 60)
				await self.endOnItsOwn(udid: udid, active: active, reason: "it reached the \(minutes)-minute limit")
			}
		}
		publishChange()
		return url
	}

	// MARK: - Stopping

	/// Stops `udid`'s recording and returns the finished file — or, when it already ended on its
	/// own, what came of that one.
	public func stop(udid: String, deviceName: String) async throws -> SimulatorRecording {
		enum Taken {
			case running(Active)
			case ended(Result<SimulatorRecording, SimulatorError>)
		}
		let taken: Taken? = state.withLock { state in
			if let active = state.active.removeValue(forKey: udid) {
				return .running(active)
			}
			return state.ended.removeValue(forKey: udid).map(Taken.ended)
		}
		switch taken {
		case let .running(active)?:
			publishChange()
			return try await finish(active, endedEarly: nil).get()
		case let .ended(result)?:
			return try result.get()
		case nil:
			throw SimulatorError.notRecording(deviceName)
		}
	}

	/// Interrupts simctl, waits for it to write the file, and checks the file is there.
	private func finish(_ active: Active, endedEarly: String?) async -> Result<SimulatorRecording, SimulatorError> {
		active.limitTask.withLock { $0?.cancel() }
		if active.process.isRunning {
			kill(active.process.processIdentifier, SIGINT)
		}
		let clock = ContinuousClock()
		let deadline = clock.now + .seconds(20)
		while active.process.isRunning, clock.now < deadline {
			try? await Task.sleep(for: .milliseconds(50))
		}
		if active.process.isRunning {
			active.process.terminate()
			return .failure(.recordingFailed("simctl did not finish writing \(active.url.lastPathComponent) within 20 seconds"))
		}
		return Self.result(of: active, endedEarly: endedEarly)
	}

	private static func result(of active: Active, endedEarly: String?) -> Result<SimulatorRecording, SimulatorError> {
		guard FileManager.default.fileExists(atPath: active.url.path(percentEncoded: false)) else {
			return .failure(.recordingFailed(active.message.isEmpty ? "simctl wrote no file" : active.message))
		}
		return .success(SimulatorRecording(url: active.url, duration: active.duration, endedEarly: endedEarly))
	}

	/// The time limit ran out: stops the recording and keeps the result for the next `stop`.
	private func endOnItsOwn(udid: String, active: Active, reason: String) async {
		guard remove(active, udid: udid) else {
			return
		}
		let result = await finish(active, endedEarly: reason)
		state.withLock { $0.ended[udid] = result }
	}

	/// simctl quit: on its own (the device shut down) unless `stop` already took the recording.
	private func processExited(udid: String, active: Active) {
		guard remove(active, udid: udid) else {
			return
		}
		active.limitTask.withLock { $0?.cancel() }
		let detail = active.message.isEmpty ? "" : " (\(active.message))"
		let result = Self.result(of: active, endedEarly: "simctl stopped recording, probably because the device shut down\(detail)")
		state.withLock { $0.ended[udid] = result }
	}

	/// Takes `active` out of the running recordings if it is still there; `false` when something
	/// else already did.
	@discardableResult
	private func remove(_ active: Active, udid: String) -> Bool {
		let removed = state.withLock { state in
			guard state.active[udid] === active else {
				return false
			}
			state.active[udid] = nil
			return true
		}
		if removed {
			publishChange()
		}
		return removed
	}

	/// Interrupts every recording and gives simctl up to 3 s to write the files, blocking the
	/// main thread while the app quits.
	private func interruptAllBeforeQuitting() {
		let running = state.withLock { state in
			defer { state.active = [:] }
			return Array(state.active.values)
		}
		for active in running where active.process.isRunning {
			kill(active.process.processIdentifier, SIGINT)
		}
		let deadline = Date.now.addingTimeInterval(3)
		while running.contains(where: \.process.isRunning), Date.now < deadline {
			usleep(50_000)
		}
	}

	// MARK: - Where it goes

	/// The file a recording of `deviceName` goes to: `requested` — a file, or an existing folder to
	/// name one in — or Simulator.app's screenshot folder. Never an existing file: simctl would
	/// refuse it without `--force`, and overwriting one the model named is not what it asked for.
	static func destination(
		requested: String?,
		deviceName: String,
		date: Date,
		defaultFolder: @autoclosure () -> URL,
		isDirectory: (URL) -> Bool,
		exists: (URL) -> Bool
	) throws(SimulatorError) -> URL {
		let name = SimulatorScreenshotFile.recordingName(deviceName: deviceName, date: date)
		guard let requested = requested?.trimmingCharacters(in: .whitespaces), !requested.isEmpty else {
			return SimulatorScreenshotFile.unusedURL(in: defaultFolder(), name: name, exists: exists)
		}

		let path = (requested as NSString).expandingTildeInPath
		guard path.hasPrefix("/") else {
			throw .recordingFailed("\"\(requested)\" is not an absolute path.")
		}
		let url = URL(fileURLWithPath: path)
		if isDirectory(url) {
			return SimulatorScreenshotFile.unusedURL(in: url, name: name, exists: exists)
		}

		let file = switch url.pathExtension.lowercased() {
		case "":
			url.appendingPathExtension("mov")
		case "mov":
			url
		default:
			throw SimulatorError.recordingFailed("simctl writes QuickTime movies; name the file .mov.")
		}
		guard isDirectory(file.deletingLastPathComponent()) else {
			throw .recordingFailed("The folder \(file.deletingLastPathComponent().path(percentEncoded: false)) does not exist.")
		}
		guard !exists(file) else {
			throw .recordingFailed("\(file.path(percentEncoded: false)) already exists.")
		}
		return file
	}
}
