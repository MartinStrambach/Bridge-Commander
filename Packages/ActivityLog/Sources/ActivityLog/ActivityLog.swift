import Foundation
import Synchronization

/// What an entry is about; the raw value is the tag the entry's line carries.
public nonisolated enum ActivityLogCategory: String, Sendable {
	case app
	case git
	case network
	case error
	case exception
}

/// A plain-text log of what the app did — git commands, network requests, errors — kept in
/// Application Support so it can be saved from Settings and shared.
///
/// `record` returns at once: every file operation runs on one serial background queue, in the
/// order entries were recorded, so neither the main thread nor the cooperative pool waits on
/// disk. Export, size and clear go through the same queue, so they see every entry recorded
/// before them. An uncaught exception's entry is the exception — it waits for the queue, so
/// it is on disk before the crash. The file is capped at `maximumFileSize`; past it the file
/// becomes the previous one (replacing the one before) and a new file starts, so the log never
/// holds more than about twice the cap.
public nonisolated final class ActivityLog: Sendable {
	/// Writes nothing in a process without a bundle identifier — a package's `swift test`, whose
	/// git commands would otherwise leave a log in Application Support on every run.
	public static let shared = ActivityLog(directory: defaultDirectory, isEnabled: Bundle.main.bundleIdentifier != nil)

	/// User defaults key of Settings' "Record read-only git commands" toggle. Read on every git
	/// command rather than observed, so this package needs no Sharing dependency.
	public static let includesReadOnlyGitCommandsKey = "activityLogIncludesReadOnlyGitCommands"

	public static var includesReadOnlyGitCommands: Bool {
		UserDefaults.standard.bool(forKey: includesReadOnlyGitCommandsKey)
	}

	public let fileURL: URL
	let previousFileURL: URL
	private let maximumFileSize: UInt64
	private let isEnabled: Bool
	/// Where every file operation runs.
	private let queue = DispatchQueue(label: "ActivityLog", qos: .utility)
	/// The open file, nil until the first write after launch, a rotation or a clear. Only ever
	/// locked on `queue`, so never contended; the lock is what lets the compiler check the class
	/// is `Sendable`.
	private let file = Mutex<FileHandle?>(nil)

	/// Marks `queue`, so the exception handler and `flush` can tell they run on it.
	private static let queueKey = DispatchSpecificKey<Void>()

	init(directory: URL, maximumFileSize: UInt64 = 2_000_000, isEnabled: Bool = true) {
		fileURL = directory.appending(component: "activity.log")
		previousFileURL = directory.appending(component: "activity.previous.log")
		self.maximumFileSize = maximumFileSize
		self.isEnabled = isEnabled
		queue.setSpecific(key: Self.queueKey, value: ())
	}

	/// `Application Support/<bundle id>/Logs`, beside the app's other files; a debug build's
	/// bundle identifier differs, so it keeps its own log.
	private static var defaultDirectory: URL {
		let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
			?? URL(filePath: NSHomeDirectory()).appending(path: "Library/Application Support")
		return appSupport
			.appending(component: Bundle.main.bundleIdentifier ?? "BridgeCommander")
			.appending(component: "Logs")
	}

	// MARK: - Recording

	/// Appends one entry. `details` (stderr, a response body, a call stack) goes on the
	/// following lines, indented, so every entry still starts with its timestamp.
	public func record(_ category: ActivityLogCategory, _ message: String, details: String? = nil) {
		guard isEnabled else {
			return
		}

		let date = Date.now
		queue.async { [self] in
			write(Data(Self.line(date: date, category: category, message: message, details: details).utf8))
		}
	}

	/// Records a thrown error with what was being done when it was thrown. Cancellation is not
	/// recorded: it is how a superseded refresh ends, not something that went wrong.
	public func record(_ error: any Error, context: String) {
		guard !Self.isCancellation(error) else {
			return
		}

		record(.error, "\(context): \(Self.describe(error))")
	}

	/// Runs `operation`, recording what it throws before rethrowing it. Errors `isExpected`
	/// accepts (a token not configured yet, which every refresh would otherwise repeat) are
	/// rethrown unrecorded.
	public func recordingErrors<T>(
		_ context: @autoclosure () -> String,
		unless isExpected: (any Error) -> Bool = { _ in false },
		_ operation: () async throws -> T
	) async throws -> T {
		do {
			return try await operation()
		}
		catch {
			if !isExpected(error) {
				record(error, context: context())
			}
			throw error
		}
	}

	// MARK: - Exporting

	/// The whole log, the previous file first, under a header describing the app and the Mac, as
	/// a file to attach to a bug report.
	public func exportData() async -> Data {
		await onQueue { [self] in
			var data = Data(Self.exportHeader().utf8)
			for url in [previousFileURL, fileURL] {
				if let contents = try? Data(contentsOf: url) {
					data.append(contents)
				}
			}
			return data
		}
	}

	/// Total size of the log on disk, for Settings to show.
	public func size() async -> UInt64 {
		await onQueue { [self] in
			[previousFileURL, fileURL]
				.compactMap { try? FileManager.default.attributesOfItem(atPath: $0.path)[.size] as? UInt64 }
				.reduce(0, +)
		}
	}

	public func clear() async {
		await onQueue { [self] in
			file.withLock { handle in
				try? handle?.close()
				handle = nil
			}
			try? FileManager.default.removeItem(at: fileURL)
			try? FileManager.default.removeItem(at: previousFileURL)
		}
	}

	/// Blocks until every entry recorded so far is written — for the app's termination, which
	/// would otherwise drop what is still queued.
	public func flush() {
		guard DispatchQueue.getSpecific(key: Self.queueKey) == nil else {
			return
		}

		queue.sync {}
	}

	private func onQueue<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
		await withCheckedContinuation { continuation in
			queue.async {
				continuation.resume(returning: work())
			}
		}
	}

	// MARK: - Exceptions

	/// Records an Objective-C exception nothing caught, with its call stack, before the app
	/// terminates. AppKit catches exceptions raised on the main thread inside event handling and
	/// only logs them to the console, so those never reach this handler.
	public static func installUncaughtExceptionHandler() {
		NSSetUncaughtExceptionHandler { exception in
			ActivityLog.shared.recordBeforeCrash(
				"Uncaught \(exception.name.rawValue): \(exception.reason ?? "no reason")",
				details: exception.callStackSymbols.joined(separator: "\n")
			)
		}
	}

	/// Writes an exception's entry before returning, after everything already queued. Raised on
	/// the queue itself, it may have interrupted a write holding the file's lock, so it only tries
	/// the lock: losing the entry beats deadlocking a crashing app.
	private func recordBeforeCrash(_ message: String, details: String) {
		guard isEnabled else {
			return
		}

		let data = Data(Self.line(date: .now, category: .exception, message: message, details: details).utf8)
		if DispatchQueue.getSpecific(key: Self.queueKey) != nil {
			write(data, waitingForLock: false)
		}
		else {
			queue.sync { write(data) }
		}
	}

	// MARK: - Writing

	/// Runs on `queue` only.
	private func write(_ data: Data, waitingForLock: Bool = true) {
		if waitingForLock {
			file.withLock { append(data, to: &$0) }
		}
		else {
			_ = file.withLockIfAvailable { append(data, to: &$0) }
		}
	}

	private func append(_ data: Data, to handle: inout FileHandle?) {
		if handle == nil {
			handle = openFile()
		}
		guard let current = handle else {
			return
		}

		do {
			try current.write(contentsOf: data)
			if try current.offset() > maximumFileSize {
				try? current.close()
				handle = nil
				rotate()
			}
		}
		catch {
			// A file that cannot be written (disk full, deleted directory) is reopened next time.
			try? current.close()
			handle = nil
		}
	}

	private func openFile() -> FileHandle? {
		let fileManager = FileManager.default
		try? fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
		if !fileManager.fileExists(atPath: fileURL.path) {
			fileManager.createFile(atPath: fileURL.path, contents: nil)
		}
		guard let handle = try? FileHandle(forWritingTo: fileURL) else {
			return nil
		}

		_ = try? handle.seekToEnd()
		return handle
	}

	private func rotate() {
		let fileManager = FileManager.default
		try? fileManager.removeItem(at: previousFileURL)
		try? fileManager.moveItem(at: fileURL, to: previousFileURL)
	}

	// MARK: - Formatting

	private static let timestampStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true, timeZone: .current)

	/// One entry: `<timestamp> [<category>] <message>`, then `details` indented by four spaces.
	/// The home folder is written as `~`, so a shared log does not carry the user's account name.
	static func line(date: Date, category: ActivityLogCategory, message: String, details: String?) -> String {
		var line = "\(date.formatted(timestampStyle)) [\(category.rawValue)] \(message)\n"
		if let details, !details.isEmpty {
			for detail in details.split(separator: "\n", omittingEmptySubsequences: false) {
				line += "    \(detail)\n"
			}
		}
		return abbreviatingHome(line)
	}

	static func abbreviatingHome(_ text: String, home: String = NSHomeDirectory()) -> String {
		guard !home.isEmpty, home != "/" else {
			return text
		}

		return text.replacing(home, with: "~")
	}

	/// An error as a line: a Foundation error by its domain and code (`NSURLErrorDomain -1009`),
	/// which is what to search for; anything else by its full type and case, e.g.
	/// `GitHosting.GitHostingError.httpFailure(statusCode: 401)`, or a `DecodingError` with the
	/// coding path it failed at.
	static func describe(_ error: any Error) -> String {
		if let urlError = error as? URLError {
			return "\(NSURLErrorDomain) \(urlError.errorCode): \(urlError.localizedDescription)"
		}
		if let cocoaError = error as? CocoaError {
			return "\(NSCocoaErrorDomain) \(cocoaError.errorCode): \(cocoaError.localizedDescription)"
		}
		if type(of: error) is NSError.Type {
			let nsError = error as NSError
			return "\(nsError.domain) \(nsError.code): \(nsError.localizedDescription)"
		}
		return String(reflecting: error)
	}

	static func isCancellation(_ error: any Error) -> Bool {
		if error is CancellationError {
			return true
		}
		if let urlError = error as? URLError {
			return urlError.code == .cancelled
		}
		return false
	}

	private static func exportHeader() -> String {
		let info = Bundle.main.infoDictionary ?? [:]
		let name = info["CFBundleDisplayName"] as? String ?? info["CFBundleName"] as? String ?? "Bridge Commander"
		let version = info["CFBundleShortVersionString"] as? String ?? "?"
		return """
		\(name) \(version) (\(Bundle.main.bundleIdentifier ?? "?"))
		\(ProcessInfo.processInfo.operatingSystemVersionString)
		Exported \(Date.now.formatted(timestampStyle))

		"""
	}
}
