import Foundation

/// The `list_crashes` and `crash_report` tools.
nonisolated enum SimulatorCrashReports {
	enum Failure: Error, Equatable, LocalizedError {
		case invalidName(String)
		case notFound(String)
		case notACrashReport(String)

		var errorDescription: String? {
			switch self {
			case let .invalidName(name):
				"\"\(name)\" is not a crash report name: pass a file name from list_crashes, such as MyApp-2026-10-07-193214.ips."
			case let .notFound(name):
				"No crash report named \(name). list_crashes shows the recent ones."
			case let .notACrashReport(name):
				"\(name) is not a crash report this tool can read."
			}
		}
	}

	static let defaultSinceMinutes = 60.0
	static let defaultLimit = 10
	/// Reading is bounded even for a wide window: the folder keeps hundreds of reports.
	static let maxFilesRead = 400

	// MARK: - list_crashes

	struct ListRequest: Equatable {
		/// Only this simulator's crashes; nil for every simulator's.
		var udid: String?
		var deviceName: String?
		var bundleID: String?
		var sinceMinutes = defaultSinceMinutes
		var limit = defaultLimit
		var includeSystem = false
	}

	/// The tool's arguments. Without a `udid` it is the device the other tools would act on —
	/// else the shown one even when shut down, since a crash can outlive the boot — and with no
	/// device at all, every simulator.
	static func listRequest(arguments: JSONValue, actions: any SimulatorToolActions) async -> ListRequest {
		var request = ListRequest(
			bundleID: arguments["bundle_id"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 },
			includeSystem: arguments["include_system"] == .bool(true) || arguments["include_system"] == "true"
		)
		if let minutes = arguments["since_minutes"]?.doubleValue, minutes.isFinite {
			request.sinceMinutes = min(max(minutes, 1), 30 * 24 * 60)
		}
		if let limit = arguments["limit"]?.doubleValue, limit.isFinite {
			request.limit = Int(min(max(limit, 1), 50))
		}

		let devices = (try? await actions.devices()) ?? []
		if let udid = arguments["udid"]?.stringValue, !udid.isEmpty {
			request.udid = udid.uppercased()
		}
		else if let device = try? await actions.resolveDevice(udid: nil) {
			request.udid = device.id
		}
		else {
			request.udid = actions.selectedDeviceId?.uppercased()
		}
		request.deviceName = request.udid.flatMap { udid in
			devices.first { $0.id.caseInsensitiveCompare(udid) == .orderedSame }?.name
		}
		return request
	}

	static func list(_ request: ListRequest, source: any SimulatorCrashReportSource, now: Date = Date()) async throws -> String {
		let cutoff = now.addingTimeInterval(-request.sinceMinutes * 60)
		// A file is modified no earlier than the crash it records, so the cheap date filters out
		// old reports without reading them; the report's own time decides.
		let candidates = try await source.reportFiles()
			.filter { $0.modified >= cutoff }
			.sorted { $0.modified > $1.modified }
			.prefix(maxFilesRead)

		var matches: [SimulatorCrashReport] = []
		var hiddenSystem = 0
		for file in candidates {
			guard let contents = try? await source.contents(ofReport: file.name) else {
				continue
			}
			// Every simulator report names its device's coalition; skip Mac crashes unparsed.
			guard contents.contains(request.udid?.uppercased() ?? "CoreSimulator") else {
				continue
			}
			guard
				let report = SimulatorCrashReport.parse(fileName: file.name, contents: contents),
				let udid = report.deviceUDID,
				request.udid.map({ $0.caseInsensitiveCompare(udid) == .orderedSame }) ?? true,
				(report.time ?? file.modified) >= cutoff
			else {
				continue
			}
			if let bundleID = request.bundleID {
				guard report.bundleID?.caseInsensitiveCompare(bundleID) == .orderedSame else {
					continue
				}
			}
			else if !request.includeSystem, !report.isInstalledApp {
				hiddenSystem += 1
				continue
			}
			matches.append(report)
		}
		matches.sort { ($0.time ?? .distantPast) > ($1.time ?? .distantPast) }

		let scope = [
			request.bundleID,
			request.deviceName.map { "on \($0)" } ?? request.udid.map { "on \($0)" } ?? "on any simulator",
		]
		.compactMap(\.self)
		.joined(separator: " ")
		let window = "in the last \(minutesText(request.sinceMinutes))"

		var lines: [String] = []
		if matches.isEmpty {
			lines.append("No crashes \(scope) \(window).")
		}
		else {
			let shown = matches.prefix(request.limit)
			lines.append("\(matches.count) crash\(matches.count == 1 ? "" : "es") \(scope) \(window), newest first"
				+ (shown.count < matches.count ? " (showing \(shown.count))" : "") + ":")
			lines += shown.map { SimulatorCrashReportFormatter.listLine($0, now: now) }
			lines.append("crash_report with a file name shows the backtrace.")
		}
		if hiddenSystem > 0 {
			lines.append("\(hiddenSystem) crash\(hiddenSystem == 1 ? "" : "es") of the simulator's own processes not shown; include_system lists them.")
		}
		return SimulatorCrashReportFormatter.capped(lines.joined(separator: "\n"))
	}

	private static func minutesText(_ minutes: Double) -> String {
		let whole = Int(minutes.rounded())
		if whole >= 120, whole % 60 == 0 {
			return "\(whole / 60) hours"
		}
		return whole == 1 ? "minute" : "\(whole) minutes"
	}

	// MARK: - crash_report

	static func report(named name: String, source: any SimulatorCrashReportSource) async throws -> String {
		let name = try validatedName(name)
		let contents = try await source.contents(ofReport: name)
		guard let report = SimulatorCrashReport.parse(fileName: name, contents: contents) else {
			throw Failure.notACrashReport(name)
		}
		var messages: [String] = []
		if report.applicationSpecificInformation.isEmpty, let udid = report.deviceUDID, let pid = report.pid, let time = report.time {
			messages = await source.crashMessages(udid: udid, pid: pid, at: time)
		}
		return SimulatorCrashReportFormatter.summary(report, logMessages: messages)
	}

	/// A bare `.ips` file name: the tool reads only the reports folder, so anything that could
	/// name a path — separators, `..`, a leading dot — is refused rather than resolved.
	static func validatedName(_ name: String) throws -> String {
		let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
		guard
			!name.isEmpty,
			!name.hasPrefix("."),
			name.hasSuffix(".ips"),
			!name.contains("/"),
			!name.contains("\\"),
			!name.contains(":"),
			!name.contains("\0"),
			!name.contains(where: \.isNewline)
		else {
			throw Failure.invalidName(name)
		}
		return name
	}

	// MARK: - The device log

	/// Messages a crashing process logs about why: CoreFoundation's "Terminating app due to
	/// uncaught exception", the Swift runtime's fatal errors (logged from libswiftCore), and
	/// libc++abi's uncaught C++ exception.
	static let crashMessagePredicate = """
		eventMessage CONTAINS "Terminating app due to uncaught exception" \
		OR senderImagePath ENDSWITH "/libswiftCore.dylib" \
		OR eventMessage BEGINSWITH "libc++abi: terminating"
		"""

	/// `log show` arguments for the minute before the crash, pinned to the process. The report's
	/// capture time trails the crash by a second or so.
	static func logArguments(pid: Int, at time: Date) -> [String] {
		let window = logWindow(around: time)
		return [
			"show", "--style", "compact", "--start", window.start, "--end", window.end,
			"--predicate", "processID == \(pid) AND (\(crashMessagePredicate))",
		]
	}

	/// `log show --start/--end` values: the minute before `time` to just after, in UTC so the
	/// simulator's time zone does not matter.
	static func logWindow(around time: Date) -> (start: String, end: String) {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.timeZone = TimeZone(identifier: "UTC")
		formatter.dateFormat = "yyyy-MM-dd HH:mm:ssZ"
		return (formatter.string(from: time.addingTimeInterval(-60)), formatter.string(from: time.addingTimeInterval(5)))
	}

	/// The messages in `log show --style compact` output: each entry starts with a timestamp and
	/// `Process[pid:tid]`; the lines after it (an exception's "First throw call stack") are left
	/// out, since the report has the backtrace symbolicated.
	static func crashMessages(fromLog output: String, limit: Int = 4) -> [String] {
		var messages: [String] = []
		for line in output.split(whereSeparator: \.isNewline) {
			guard
				line.count > 24,
				line.prefix(4).allSatisfy(\.isNumber),
				line.dropFirst(4).first == "-",
				let processEnd = line.range(of: "] ")
			else {
				continue
			}
			let message = line[processEnd.upperBound...].trimmingCharacters(in: .whitespaces)
			if !message.isEmpty, !messages.contains(message) {
				messages.append(message)
			}
			if messages.count == limit {
				break
			}
		}
		return messages
	}
}
