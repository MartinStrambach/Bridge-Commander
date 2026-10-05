import Darwin
import Foundation

/// Finds the Claude Code conversation running in a pane, and builds the command that resumes it.
///
/// Claude Code keeps a record of every running interactive process at
/// `<config dir>/sessions/<pid>.json`, holding the `sessionId` of the conversation it is in (the
/// name of its transcript under `projects/`, and what `claude --resume` takes), and removes it
/// when the process exits. The file is Claude Code's own, not a documented interface, so anything
/// unexpected in it reads as "no session" rather than failing.
public enum ClaudeSession {
	/// The conversation Claude Code is in, if it holds the foreground of the terminal behind
	/// `ptyDescriptor`.
	///
	/// Every process of the foreground group is considered, not only its leader: a wrapper script
	/// that runs `claude` as its child leads the group itself. Only a process that is Claude by its
	/// arguments is looked up, so a record left behind by a crashed Claude cannot be attributed to
	/// whatever later reused its pid.
	static func id(
		inForegroundOf ptyDescriptor: Int32,
		sessionsDirectory: URL = defaultSessionsDirectory
	) -> String? {
		guard ptyDescriptor >= 0 else {
			return nil
		}

		for pid in PtyForegroundProcess.processes(inGroup: tcgetpgrp(ptyDescriptor)) {
			guard
				let arguments = PtyForegroundProcess.arguments(ofProcess: pid),
				PtyForegroundProcess.isClaude(arguments: arguments),
				let data = try? Data(contentsOf: sessionsDirectory.appending(component: "\(pid).json"))
			else {
				continue
			}

			if let id = id(fromRecord: data, processId: pid) {
				return id
			}
		}
		return nil
	}

	/// The session id in a `sessions/<pid>.json` record, provided the record is the one for `pid`
	/// and the id is one `resumeCommand` can safely type.
	static func id(fromRecord data: Data, processId pid: pid_t) -> String? {
		struct Record: Decodable {
			let pid: Int32
			let sessionId: String
		}

		guard
			let record = try? JSONDecoder().decode(Record.self, from: data),
			record.pid == pid,
			isWellFormed(record.sessionId)
		else {
			return nil
		}

		return record.sessionId
	}

	/// What a reopened tab types to pick the conversation back up.
	public static func resumeCommand(sessionId: String) -> String? {
		isWellFormed(sessionId) ? "claude --resume \(sessionId)" : nil
	}

	/// Session ids are UUIDs. Anything else is refused rather than quoted: the id is typed into a
	/// shell, and it comes from a file this app does not own.
	private static func isWellFormed(_ sessionId: String) -> Bool {
		UUID(uuidString: sessionId) != nil
	}

	/// Claude Code's config directory: `CLAUDE_CONFIG_DIR` when set, otherwise `~/.claude`. Read
	/// from this app's environment — a value exported only from the user's shell profile is not
	/// seen here, and the default is assumed.
	static var defaultSessionsDirectory: URL {
		let configured = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] ?? ""
		let configDirectory = configured.isEmpty
			? URL(fileURLWithPath: NSHomeDirectory()).appending(component: ".claude")
			: URL(fileURLWithPath: (configured as NSString).expandingTildeInPath)
		return configDirectory.appending(component: "sessions")
	}
}
