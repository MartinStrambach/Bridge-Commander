import Foundation
import ProcessExecution

/// A crash report file, before it is read.
struct CrashReportFile: Equatable, Sendable {
	var name: String
	var modified: Date
}

/// Where crash reports come from: the real `DiagnosticReports` folder in the app, fixtures in
/// tests.
protocol SimulatorCrashReportSource: Sendable {
	/// The `.ips` files, in no particular order.
	func reportFiles() async throws -> [CrashReportFile]
	/// One report's text. `name` has been checked by `SimulatorCrashReports.validatedName`.
	func contents(ofReport name: String) async throws -> String
	/// What the crashed process logged as it died — an uncaught exception's reason, a Swift
	/// fatal error — which simulator reports leave out. Best effort: empty when the device is not
	/// booted or the log has rolled over.
	func crashMessages(udid: String, pid: Int, at time: Date) async -> [String]
}

/// `~/Library/Logs/DiagnosticReports`, where the host's ReportCrash writes simulator crashes too.
///
/// Only the folder itself is read: ReportCrash moves reports to `Retired/` once they have been
/// submitted or aged out, which is long after anyone debugging a crash wants them.
struct DiagnosticReportsDirectory: SimulatorCrashReportSource {
	var directory = FileManager.default.homeDirectoryForCurrentUser
		.appending(path: "Library/Logs/DiagnosticReports", directoryHint: .isDirectory)

	func reportFiles() async throws -> [CrashReportFile] {
		let urls = try FileManager.default.contentsOfDirectory(
			at: directory,
			includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
			options: [.skipsHiddenFiles]
		)
		return urls.compactMap { url in
			guard
				url.pathExtension == "ips",
				let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
				values.isRegularFile == true
			else {
				return nil
			}
			return CrashReportFile(name: url.lastPathComponent, modified: values.contentModificationDate ?? .distantPast)
		}
	}

	func contents(ofReport name: String) async throws -> String {
		let url = directory.appending(path: name, directoryHint: .notDirectory)
		// `validatedName` already refuses separators; this also catches anything it missed.
		guard url.standardizedFileURL.deletingLastPathComponent().path == directory.standardizedFileURL.path else {
			throw SimulatorCrashReports.Failure.invalidName(name)
		}
		guard FileManager.default.fileExists(atPath: url.path) else {
			throw SimulatorCrashReports.Failure.notFound(name)
		}
		return try String(contentsOf: url, encoding: .utf8)
	}

	func crashMessages(udid: String, pid: Int, at time: Date) async -> [String] {
		let result = await ProcessRunner.run(
			executableURL: URL(fileURLWithPath: "/usr/bin/xcrun"),
			arguments: ["simctl", "spawn", udid, "log"] + SimulatorCrashReports.logArguments(pid: pid, at: time),
			environment: EnvironmentHelper.setupEnvironment()
		)
		guard result.success else {
			return []
		}
		return SimulatorCrashReports.crashMessages(fromLog: result.outputString)
	}
}
