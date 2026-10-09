import AppKit
import Foundation
import os
import ProcessExecution

/// What `launch_app` launches.
public struct SimulatorAppLaunchRequest: Equatable, Sendable {
	public var bundleId: String
	public var arguments: [String]
	/// Passed to the app; simctl takes them from its own environment with a `SIMCTL_CHILD_` prefix.
	public var environment: [String: String]
	public var captureLogs: Bool
	/// A `log stream` predicate replacing `SimulatorAppLauncher.defaultLogPredicate`.
	public var logPredicate: String?

	public init(
		bundleId: String,
		arguments: [String] = [],
		environment: [String: String] = [:],
		captureLogs: Bool = true,
		logPredicate: String? = nil
	) {
		self.bundleId = bundleId
		self.arguments = arguments
		self.environment = environment
		self.captureLogs = captureLogs
		self.logPredicate = logPredicate
	}
}

/// An app `launch_app` launched.
public struct SimulatorAppLaunch: Equatable, Sendable {
	public var processId: Int?
	/// Where its output and log go; `nil` when launched without capture.
	public var logURL: URL?
	/// The `log stream` predicate the log is filtered by.
	public var logPredicate: String?

	public init(processId: Int?, logURL: URL? = nil, logPredicate: String? = nil) {
		self.processId = processId
		self.logURL = logURL
		self.logPredicate = logPredicate
	}
}

/// Launches apps in a simulator with what they print and log going to one file, so Claude can read
/// an app's output as Xcode's console shows it.
///
/// Two processes write to the file, opened `O_APPEND` so their lines interleave rather than
/// overwrite each other: `simctl launch --console-pty`, which runs as long as the app does and
/// relays its stdout and stderr (`print`, `NSLog`) — a PTY, so the app's output stays line
/// buffered — and `simctl spawn <udid> log stream`, for `Logger` / `os_log`. The capture ends with
/// the app: when the launch process exits (the app quit, crashed, was terminated, or launched again
/// with `--terminate-running-process`), the log stream is stopped a second later. simctl prints the
/// app's pid only when it exits (its stdout is a file, so buffered), so the pid comes from a second,
/// idempotent `simctl launch`, which brings the running app forward and names it — as
/// MobileBuildMCP does. The same approach as MobileBuildMCP's `launch_app_sim`.
public final class SimulatorAppLauncher: @unchecked Sendable {
	public static let shared = SimulatorAppLauncher()
	/// Logs older than this are deleted when a new one is started.
	static let retention: TimeInterval = 7 * 24 * 60 * 60

	private struct Key: Hashable {
		let udid: String
		let bundleId: String
	}

	private final class Capture: @unchecked Sendable {
		let console: Process
		let logStream: Process
		let file: FileHandle
		let url: URL

		init(console: Process, logStream: Process, file: FileHandle, url: URL) {
			self.console = console
			self.logStream = logStream
			self.file = file
			self.url = url
		}
	}

	private let captures = OSAllocatedUnfairLock<[Key: Capture]>(uncheckedState: [:])

	private init() {
		NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { [weak self] _ in
			self?.stopAllBeforeQuitting()
		}
	}

	// MARK: - Launching

	public func launch(udid: String, deviceName: String, _ request: SimulatorAppLaunchRequest) async throws -> SimulatorAppLaunch {
		let host = SimulatorHost.shared
		let appPath: String
		do {
			appPath = try await host.simctl(["get_app_container", udid, request.bundleId, "app"])
				.trimmingCharacters(in: .whitespacesAndNewlines)
		}
		catch {
			throw SimulatorError.appNotInstalled(bundleId: request.bundleId, device: deviceName)
		}
		let environment = Self.childEnvironment(request.environment)

		guard request.captureLogs else {
			let output = try await host.simctl(
				["launch", "--terminate-running-process", udid, request.bundleId] + request.arguments,
				extraEnvironment: environment
			)
			return SimulatorAppLaunch(processId: Self.processId(fromLaunchOutput: output))
		}

		let executable = Self.executableName(appPath: appPath)
		let predicate = request.logPredicate ?? Self.defaultLogPredicate(bundleId: request.bundleId, executable: executable)
		let url = try Self.createLogFile(bundleId: request.bundleId, in: Self.defaultFolder(), date: .now)
		let file = try Self.openForAppending(url)
		file.write(Data("""
		# \(request.bundleId) on \(deviceName) (\(udid)), launched \(Date.ISO8601FormatStyle(timeZone: .current).format(.now)).
		# Its stdout and stderr, and its os_log messages matching: \(predicate)

		""".utf8))

		let logStream = Self.simctlProcess(
			["spawn", udid, "log", "stream", "--style", "compact", "--level", "debug", "--predicate", predicate],
			output: file
		)
		do {
			try logStream.run()
		}
		catch {
			throw SimulatorError.launchFailed("could not start `log stream`: \(error.localizedDescription)")
		}
		// The stream takes a moment to attach; started after the app, it would miss its first lines.
		try? await Task.sleep(for: .milliseconds(700))

		let console = Self.simctlProcess(
			["launch", "--console-pty", "--terminate-running-process", udid, request.bundleId] + request.arguments,
			output: file,
			extraEnvironment: environment
		)
		let key = Key(udid: udid, bundleId: request.bundleId)
		let capture = Capture(console: console, logStream: logStream, file: file, url: url)
		console.terminationHandler = { [weak self] process in
			self?.consoleExited(key: key, capture: capture, status: process.terminationStatus)
		}
		do {
			try console.run()
		}
		catch {
			logStream.terminate()
			throw SimulatorError.launchFailed("could not run `simctl launch`: \(error.localizedDescription)")
		}
		// A capture of an earlier launch ends on its own: --terminate-running-process ends its app.
		captures.withLock { $0[key] = capture }

		try? await Task.sleep(for: .milliseconds(500))
		guard console.isRunning else {
			let tail = Self.lastLines(of: url, count: 20)
			throw SimulatorError.launchFailed("simctl exited at once (status \(console.terminationStatus)). The end of \(url.path(percentEncoded: false)):\n\(tail)")
		}
		let processId = try? await Self.processId(fromLaunchOutput: host.simctl(["launch", udid, request.bundleId]))
		return SimulatorAppLaunch(processId: processId, logURL: url, logPredicate: predicate)
	}

	/// Terminates the app, which ends its capture, and returns the log it was captured to.
	public func terminate(udid: String, bundleId: String) async throws -> URL? {
		let url = captures.withLock { $0[Key(udid: udid, bundleId: bundleId)]?.url }
		try await SimulatorHost.shared.simctl(["terminate", udid, bundleId])
		return url
	}

	/// The app ended: the log stream gets a second for the app's last messages, then stops, and
	/// the file is closed with a line saying how the app ended.
	private func consoleExited(key: Key, capture: Capture, status: Int32) {
		captures.withLock { captures in
			if captures[key] === capture {
				captures[key] = nil
			}
		}
		DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
			if capture.logStream.isRunning {
				capture.logStream.terminate()
			}
			capture.logStream.waitUntilExit()
			capture.file.write(Data("# \(key.bundleId) exited; simctl launch ended with status \(status).\n".utf8))
			try? capture.file.close()
		}
	}

	/// Ends every capture when the app quits — stopping the apps too, since simctl passes the
	/// signal on to them, as quitting Xcode stops what it ran.
	private func stopAllBeforeQuitting() {
		let running = captures.withLock { captures in
			defer { captures = [:] }
			return Array(captures.values)
		}
		for capture in running {
			for process in [capture.console, capture.logStream] where process.isRunning {
				process.terminate()
			}
		}
	}

	// MARK: - Helpers

	private static func simctlProcess(_ arguments: [String], output: FileHandle, extraEnvironment: [String: String] = [:]) -> Process {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
		process.arguments = ["simctl"] + arguments
		process.environment = EnvironmentHelper.setupEnvironment().merging(extraEnvironment) { $1 }
		process.standardInput = FileHandle.nullDevice
		process.standardOutput = output
		process.standardError = output
		return process
	}

	private static func openForAppending(_ url: URL) throws -> FileHandle {
		let descriptor = open(url.path(percentEncoded: false), O_WRONLY | O_CREAT | O_APPEND, 0o644)
		guard descriptor >= 0 else {
			throw SimulatorError.launchFailed("could not create \(url.path(percentEncoded: false)): \(String(cString: strerror(errno)))")
		}
		return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
	}

	/// `~/Library/Logs/<bundle id>/Simulator Apps`: Console.app lists it, and the debug build keeps
	/// its own.
	static func defaultFolder() -> URL {
		let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
			?? URL(fileURLWithPath: NSHomeDirectory()).appending(component: "Library")
		return library
			.appending(component: "Logs")
			.appending(component: Bundle.main.bundleIdentifier ?? "BridgeCommander")
			.appending(component: "SimulatorApps")
	}

	/// A new, empty file for `bundleId`'s log in `folder`, after deleting logs older than
	/// `retention`.
	private static func createLogFile(bundleId: String, in folder: URL, date: Date) throws -> URL {
		let fileManager = FileManager.default
		try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
		let old = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
		for url in old {
			let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
			if let modified, date.timeIntervalSince(modified) > retention {
				try? fileManager.removeItem(at: url)
			}
		}
		var url = folder.appending(component: logFileName(bundleId: bundleId, date: date))
		var number = 2
		while fileManager.fileExists(atPath: url.path(percentEncoded: false)) {
			url = folder.appending(component: logFileName(bundleId: bundleId, date: date, number: number))
			number += 1
		}
		return url
	}

	/// "com.example.App_2026-10-10_14-03-05.log" — no spaces, so the path needs no quoting in a shell.
	static func logFileName(bundleId: String, date: Date, number: Int? = nil) -> String {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
		let safe = bundleId.map { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" ? $0 : "_" }
		return "\(String(safe))_\(formatter.string(from: date))\(number.map { "_\($0)" } ?? "").log"
	}

	/// The app's own messages — its subsystem, the bundle id or one under it, as `Logger` is
	/// usually set up — and every error and fault in its process, whichever framework logged it.
	/// The whole process at debug level would bury them under UIKit's and CFNetwork's chatter.
	static func defaultLogPredicate(bundleId: String, executable: String) -> String {
		"process == \(quoted(executable)) AND (subsystem BEGINSWITH \(quoted(bundleId)) OR messageType == error OR messageType == fault)"
	}

	private static func quoted(_ value: String) -> String {
		"\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
	}

	/// The app's executable — the process name `log stream` filters by — from its Info.plist, else
	/// the bundle's name.
	static func executableName(appPath: String) -> String {
		let url = URL(fileURLWithPath: appPath)
		let info = NSDictionary(contentsOf: url.appending(component: "Info.plist"))
		return info?["CFBundleExecutable"] as? String ?? url.deletingPathExtension().lastPathComponent
	}

	/// `SIMCTL_CHILD_` before each name not already carrying it.
	static func childEnvironment(_ environment: [String: String]) -> [String: String] {
		let prefix = "SIMCTL_CHILD_"
		return Dictionary(uniqueKeysWithValues: environment.map { name, value in
			(name.hasPrefix(prefix) ? name : prefix + name, value)
		})
	}

	/// The pid from `simctl launch`'s "com.example.App: 1234".
	static func processId(fromLaunchOutput output: String) -> Int? {
		output.split(whereSeparator: \.isNewline)
			.compactMap { line in line.split(separator: ":").last.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) } }
			.first
	}

	private static func lastLines(of url: URL, count: Int) -> String {
		let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
		return text.split(whereSeparator: \.isNewline).suffix(count).joined(separator: "\n")
	}
}
