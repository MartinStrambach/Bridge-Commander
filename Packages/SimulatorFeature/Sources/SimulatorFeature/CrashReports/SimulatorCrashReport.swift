import Foundation

/// One crash report (`.ips`) from `~/Library/Logs/DiagnosticReports`, reduced to what a model
/// needs to understand the crash.
///
/// An `.ips` file (macOS 12+) is two JSON documents: a one-line header (`app_name`, `bundleID`,
/// `timestamp`, `bug_type` — 309 is a crash) and the report body (`exception`, `termination`,
/// `threads`, `usedImages`, …). Reports from simulator processes are written by the host's
/// ReportCrash like any Mac crash; what marks them is `coalitionName`
/// (`com.apple.CoreSimulator.SimDevice.<UDID>`), present on every one, and for installed apps also
/// `procPath` (`…/CoreSimulator/Devices/<UDID>/data/Containers/Bundle/Application/…`). Paths of
/// the runtime's own processes are anonymised to `/Volumes/VOLUME/*/…`, so they carry no UDID.
///
/// Simulator reports have no `asi` (application-specific information): an uncaught exception's
/// reason or a Swift `fatalError` message is only in the device's log — hence
/// `SimulatorCrashReportSource.crashMessages`.
nonisolated struct SimulatorCrashReport: Equatable, Sendable {
	struct Frame: Equatable, Sendable {
		var image: String?
		var symbol: String?
		var symbolOffset: Int?
		var imageOffset: UInt64?
		var address: UInt64?
		var sourceFile: String?
		var sourceLine: Int?
	}

	struct Thread: Equatable, Sendable {
		var index: Int
		var name: String?
		var queue: String?
		var frames: [Frame]
	}

	/// The report's file name — the id `crash_report` takes.
	var fileName: String
	var appName: String
	var bundleID: String?
	var appVersion: String?
	var buildVersion: String?
	/// When the crash was captured (`captureTime`), else when the report was written.
	var time: Date?
	var timeText: String?
	var launchTimeText: String?
	var pid: Int?
	var procPath: String?
	/// The simulator the process ran in; nil for a Mac process.
	var deviceUDID: String?
	var exceptionType: String?
	var exceptionSignal: String?
	var exceptionSubtype: String?
	var exceptionMessage: String?
	var exceptionCodes: String?
	var termination: String?
	/// `asi`, flattened to "image: message" lines.
	var applicationSpecificInformation: [String] = []
	var lastExceptionBacktrace: [Frame] = []
	var crashedThread: Thread?
	/// The executable's image name, to pick the app's own frames out of a backtrace.
	var mainImage: String?

	var isSimulator: Bool {
		deviceUDID != nil
	}

	/// An app installed on the device (Xcode, `simctl install`) or one of its extensions, rather
	/// than a process of the simulator runtime — PosterBoard, intelligence daemons and the like
	/// crash often in recent runtimes and would bury the app being worked on.
	var isInstalledApp: Bool {
		procPath?.contains("/Containers/Bundle/Application/") == true
	}

	static let crashBugType = "309"
	static let simDeviceCoalitionPrefix = "com.apple.CoreSimulator.SimDevice."

	/// Parses a report; nil when it is not a crash report in the JSON format.
	static func parse(fileName: String, contents: String) -> SimulatorCrashReport? {
		let (headerLine, body) = split(contents)
		guard
			let header = jsonObject(headerLine),
			header["bug_type"] as? String == crashBugType,
			let report = jsonObject(body)
		else {
			return nil
		}

		let bundleInfo = report["bundleInfo"] as? [String: Any]
		var result = SimulatorCrashReport(
			fileName: fileName,
			appName: (header["app_name"] as? String) ?? (report["procName"] as? String) ?? (header["name"] as? String) ?? fileName,
			bundleID: (header["bundleID"] as? String) ?? (bundleInfo?["CFBundleIdentifier"] as? String),
			appVersion: (header["app_version"] as? String) ?? (bundleInfo?["CFBundleShortVersionString"] as? String),
			buildVersion: (header["build_version"] as? String) ?? (bundleInfo?["CFBundleVersion"] as? String)
		)

		let timeText = (report["captureTime"] as? String) ?? (header["timestamp"] as? String)
		result.timeText = timeText.map(trimmingFraction)
		result.time = timeText.flatMap(date)
		result.launchTimeText = (report["procLaunch"] as? String).map(trimmingFraction)
		result.pid = integer(report["pid"])
		result.procPath = report["procPath"] as? String
		result.deviceUDID = deviceUDID(coalitionName: report["coalitionName"] as? String, procPath: result.procPath)

		if let exception = report["exception"] as? [String: Any] {
			result.exceptionType = exception["type"] as? String
			result.exceptionSignal = exception["signal"] as? String
			result.exceptionSubtype = exception["subtype"] as? String
			result.exceptionMessage = exception["message"] as? String
			result.exceptionCodes = exception["codes"] as? String
		}
		result.termination = (report["termination"] as? [String: Any]).flatMap(terminationText)
		result.applicationSpecificInformation = asiLines(report["asi"])

		let images = (report["usedImages"] as? [[String: Any]]) ?? []
		if let procPath = result.procPath {
			result.mainImage = images.first(where: { $0["path"] as? String == procPath })?["name"] as? String
		}
		result.mainImage = result.mainImage ?? images.first?["name"] as? String
		result.lastExceptionBacktrace = frames(report["lastExceptionBacktrace"], images: images)

		let threads = (report["threads"] as? [[String: Any]]) ?? []
		let crashedIndex = integer(report["faultingThread"]) ?? threads.firstIndex(where: { $0["triggered"] as? Bool == true })
		if let crashedIndex, threads.indices.contains(crashedIndex) {
			let thread = threads[crashedIndex]
			result.crashedThread = Thread(
				index: crashedIndex,
				name: thread["name"] as? String,
				queue: thread["queue"] as? String,
				frames: frames(thread["frames"], images: images)
			)
		}
		return result
	}

	/// The first line is the header; the body is the rest. Older single-document reports put
	/// everything in one object, which then serves as both.
	private static func split(_ contents: String) -> (header: Substring, body: Substring) {
		guard let newline = contents.firstIndex(of: "\n") else {
			return (contents[...], contents[...])
		}
		let body = contents[contents.index(after: newline)...]
		return (contents[..<newline], body.contains("{") ? body : contents[..<newline])
	}

	private static func jsonObject(_ text: Substring) -> [String: Any]? {
		try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
	}

	static func deviceUDID(coalitionName: String?, procPath: String?) -> String? {
		if let coalitionName, coalitionName.hasPrefix(simDeviceCoalitionPrefix) {
			let udid = coalitionName.dropFirst(simDeviceCoalitionPrefix.count)
			if !udid.isEmpty {
				return udid.uppercased()
			}
		}
		guard let procPath, let range = procPath.range(of: "/CoreSimulator/Devices/") else {
			return nil
		}
		let udid = procPath[range.upperBound...].prefix { $0 != "/" }
		return udid.count == 36 ? udid.uppercased() : nil
	}

	private static func terminationText(_ termination: [String: Any]) -> String? {
		var parts: [String] = []
		if let namespace = termination["namespace"] as? String {
			parts.append(namespace + (integer(termination["code"]).map { " \($0)" } ?? ""))
		}
		if let indicator = termination["indicator"] as? String {
			parts.append(indicator)
		}
		if let reasons = termination["reasons"] as? [String], !reasons.isEmpty {
			parts.append(reasons.joined(separator: "; "))
		}
		if let details = termination["details"] as? [String], !details.isEmpty {
			parts.append(details.joined(separator: "; "))
		}
		if let byProc = termination["byProc"] as? String {
			parts.append("by \(byProc)")
		}
		return parts.isEmpty ? nil : parts.joined(separator: ", ")
	}

	/// `asi` maps an image to its messages: `{"libsystem_c.dylib": ["abort() called"]}`.
	private static func asiLines(_ value: Any?) -> [String] {
		guard let asi = value as? [String: Any] else {
			return []
		}
		return asi.keys.sorted().flatMap { image -> [String] in
			let messages = (asi[image] as? [Any])?.compactMap { $0 as? String } ?? (asi[image] as? String).map { [$0] } ?? []
			return messages.map { "\(image): \($0)" }
		}
	}

	private static func frames(_ value: Any?, images: [[String: Any]]) -> [Frame] {
		guard let frames = value as? [[String: Any]] else {
			return []
		}
		return frames.map { frame in
			let image = integer(frame["imageIndex"]).flatMap { images.indices.contains($0) ? images[$0] : nil }
			let imageOffset = unsigned(frame["imageOffset"])
			let base = image.flatMap { unsigned($0["base"]) }
			return Frame(
				image: image?["name"] as? String,
				symbol: frame["symbol"] as? String,
				symbolOffset: integer(frame["symbolLocation"]),
				imageOffset: imageOffset,
				address: imageOffset.flatMap { offset in base.map { $0 &+ offset } },
				sourceFile: frame["sourceFile"] as? String,
				sourceLine: integer(frame["sourceLine"])
			)
		}
	}

	private static func integer(_ value: Any?) -> Int? {
		(value as? NSNumber)?.intValue
	}

	private static func unsigned(_ value: Any?) -> UInt64? {
		(value as? NSNumber)?.uint64Value
	}

	// MARK: - Times

	/// "2026-10-07 19:30:28.2904 +0200" → "2026-10-07 19:30:28 +0200": the fraction's length
	/// varies between fields, and nobody needs it.
	static func trimmingFraction(_ text: String) -> String {
		guard let dot = text.firstIndex(of: ".") else {
			return text
		}
		let rest = text[text.index(after: dot)...].drop { $0.isNumber }
		return String(text[..<dot]) + rest
	}

	static func date(_ text: String) -> Date? {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
		return formatter.date(from: trimmingFraction(text))
	}
}
