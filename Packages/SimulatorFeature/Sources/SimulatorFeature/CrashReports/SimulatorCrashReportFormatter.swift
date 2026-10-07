import Foundation

/// Crash reports as text for a model: a line per report for `list_crashes`, a readable summary
/// for `crash_report` — never the raw JSON, which runs to hundreds of kilobytes, nearly all of it
/// other threads, loaded images and VM statistics.
nonisolated enum SimulatorCrashReportFormatter {
	/// Output is capped so one report cannot flood the model's context.
	static let maxBytes = 8 * 1024
	static let crashedThreadFrames = 25
	static let exceptionBacktraceFrames = 15

	/// "19:32:10 (3 min ago)  CrashDemo 1.2 (com.example.CrashDemo)  EXC_BAD_ACCESS (SIGSEGV): … — name.ips"
	static func listLine(_ report: SimulatorCrashReport, now: Date) -> String {
		var line = report.timeText ?? "unknown time"
		if let time = report.time {
			line += " (\(age(of: time, now: now)))"
		}
		line += "  " + appDescription(report)
		line += "  " + exceptionDescription(report)
		if let reason = shortReason(report) {
			line += ": " + reason
		}
		return line + " — " + report.fileName
	}

	/// The readable summary of one report.
	static func summary(_ report: SimulatorCrashReport, logMessages: [String] = []) -> String {
		var lines: [String] = [appDescription(report)]

		var when = "Crashed \(report.timeText ?? "at an unknown time")"
		if let launch = report.launchTimeText {
			when += ", launched \(launch)"
		}
		if let pid = report.pid {
			when += ", pid \(pid)"
		}
		lines.append(when)
		if let udid = report.deviceUDID {
			lines.append("Simulator: \(udid)")
		}
		if let path = report.procPath {
			lines.append("Path: \(path)")
		}

		lines.append("Exception: " + exceptionDescription(report) + (report.exceptionSubtype.map { ", \($0)" } ?? ""))
		if let message = report.exceptionMessage {
			lines.append("Exception message: \(message)")
		}
		if let codes = report.exceptionCodes {
			lines.append("Codes: \(codes)")
		}
		if let termination = report.termination {
			lines.append("Termination: \(termination)")
		}

		if !logMessages.isEmpty {
			lines.append("")
			lines.append("From the simulator's log at the time of the crash:")
			lines += logMessages.map { "  " + oneLine($0, limit: 600) }
		}
		if !report.applicationSpecificInformation.isEmpty {
			lines.append("")
			lines.append("Application-specific information:")
			lines += report.applicationSpecificInformation.map { "  " + oneLine($0, limit: 600) }
		}
		if logMessages.isEmpty, report.applicationSpecificInformation.isEmpty, let pid = report.pid, let udid = report.deviceUDID,
		   let time = report.time {
			// Simulator reports never carry the exception's reason or a fatalError message, and
			// the log had none either (or the device is shut down): leave the model the query.
			let window = SimulatorCrashReports.logWindow(around: time)
			lines.append("")
			lines.append("The simulator's log had no crash message for this process. Its last messages, if the device is still booted: "
				+ "xcrun simctl spawn \(udid) log show --style compact --start '\(window.start)' --end '\(window.end)' "
				+ "--predicate 'processID == \(pid)'")
		}

		if !report.lastExceptionBacktrace.isEmpty {
			lines.append("")
			lines.append("Last exception backtrace:")
			lines += frameLines(report.lastExceptionBacktrace, limit: exceptionBacktraceFrames)
		}
		if let thread = report.crashedThread {
			lines.append("")
			let label = [thread.name, thread.queue].compactMap(\.self).joined(separator: ", ")
			lines.append("Crashed thread \(thread.index)\(label.isEmpty ? "" : " (\(label))"):")
			lines += frameLines(thread.frames, limit: crashedThreadFrames)
		}
		return capped(lines.joined(separator: "\n"))
	}

	// MARK: - Pieces

	static func appDescription(_ report: SimulatorCrashReport) -> String {
		var text = report.appName
		if let version = report.appVersion {
			text += " \(version)"
			if let build = report.buildVersion, build != version {
				text += " (\(build))"
			}
		}
		if let bundleID = report.bundleID {
			text += " — \(bundleID)"
		}
		return text
	}

	static func exceptionDescription(_ report: SimulatorCrashReport) -> String {
		let type = report.exceptionType ?? "Unknown exception"
		return report.exceptionSignal.map { "\(type) (\($0))" } ?? type
	}

	/// What went wrong, in a few words, for the list: the crash message if the report has one,
	/// else the kind of fault, plus the app's own frame nearest the crash.
	static func shortReason(_ report: SimulatorCrashReport) -> String? {
		var parts: [String] = []
		if let message = report.applicationSpecificInformation.first {
			parts.append(oneLine(message, limit: 160))
		}
		else if !report.lastExceptionBacktrace.isEmpty {
			parts.append("uncaught exception")
		}
		else if let subtype = report.exceptionSubtype ?? report.exceptionMessage {
			parts.append(subtype)
		}
		else if let termination = report.termination {
			parts.append(oneLine(termination, limit: 160))
		}
		if let frame = appFrame(report), let symbol = frame.symbol {
			parts.append("in \(oneLine(symbol, limit: 120))")
		}
		return parts.isEmpty ? nil : parts.joined(separator: "; ")
	}

	/// The first frame in the app's executable: where an uncaught exception was thrown from, else
	/// where the crashed thread was.
	static func appFrame(_ report: SimulatorCrashReport) -> SimulatorCrashReport.Frame? {
		guard let main = report.mainImage else {
			return nil
		}
		let frames = report.lastExceptionBacktrace + (report.crashedThread?.frames ?? [])
		return frames.first { $0.image == main }
	}

	static func frameLines(_ frames: [SimulatorCrashReport.Frame], limit: Int) -> [String] {
		var lines = frames.prefix(limit).enumerated().map { index, frame in
			"  \(index)  " + frameText(frame)
		}
		if frames.count > limit {
			lines.append("  … \(frames.count - limit) more frames")
		}
		return lines
	}

	/// `image symbol + offset (File.swift:12)`, or `image 0xaddress` for an unsymbolicated frame.
	static func frameText(_ frame: SimulatorCrashReport.Frame) -> String {
		let image = frame.image ?? "???"
		guard let symbol = frame.symbol else {
			if let address = frame.address {
				return "\(image)  0x\(String(address, radix: 16))"
			}
			return "\(image) + 0x\(String(frame.imageOffset ?? 0, radix: 16))"
		}
		var text = "\(image)  \(oneLine(symbol, limit: 300))"
		if let offset = frame.symbolOffset {
			text += " + \(offset)"
		}
		if let file = frame.sourceFile, !file.hasPrefix("/<") {
			let name = (file as NSString).lastPathComponent
			text += frame.sourceLine.map { " (\(name):\($0))" } ?? " (\(name))"
		}
		return text
	}

	static func age(of time: Date, now: Date) -> String {
		let minutes = Int(now.timeIntervalSince(time) / 60)
		switch minutes {
		case ..<1:
			return "just now"
		case ..<120:
			return "\(minutes) min ago"
		case ..<(48 * 60):
			return "\(minutes / 60) h ago"
		default:
			return "\(minutes / (24 * 60)) days ago"
		}
	}

	static func oneLine(_ text: String, limit: Int) -> String {
		let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ")
		return flat.count > limit ? String(flat.prefix(limit)) + "…" : flat
	}

	/// Cuts at a line boundary under `maxBytes` of UTF-8.
	static func capped(_ text: String, maxBytes: Int = maxBytes) -> String {
		guard text.utf8.count > maxBytes else {
			return text
		}
		var kept: [Substring] = []
		var size = 0
		let note = "… (truncated)"
		for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
			let lineSize = line.utf8.count + 1
			if size + lineSize + note.utf8.count > maxBytes {
				break
			}
			kept.append(line)
			size += lineSize
		}
		return (kept.map(String.init) + [note]).joined(separator: "\n")
	}
}
