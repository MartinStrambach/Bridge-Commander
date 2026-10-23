import Darwin

/// Who holds a pane's foreground: its shell, or a job the shell started.
enum PaneForeground: Equatable {
	/// The shell, at its prompt with no job running.
	case shell
	/// A job, by its process group. A job suspended and brought back with `fg` keeps its group.
	case job(processGroup: pid_t)
}

/// Identifies the process holding the foreground of a pseudo-terminal.
///
/// Used to set aside a status report a program left behind (its OSC 7501 records outlive a program
/// that crashed or was suspended without clearing them), and to find the Claude Code conversation
/// in a pane.
enum PtyForegroundProcess {
	/// Who holds the foreground of the terminal behind `descriptor`, whose shell is `pid`: the shell
	/// itself (it leads its own group, so at its prompt with no job running), or the process group
	/// of a job it started.
	///
	/// Returns `nil` when the foreground can't be read (closed descriptor, no foreground group).
	static func foreground(ofShell pid: pid_t, ptyDescriptor descriptor: Int32) -> PaneForeground? {
		guard descriptor >= 0, pid > 0 else {
			return nil
		}

		let foreground = tcgetpgrp(descriptor)
		guard foreground > 0 else {
			return nil
		}

		return foreground == pid ? .shell : .job(processGroup: foreground)
	}

	/// Matches the shapes Claude Code is launched in:
	/// - the native install execs a version-named binary with `argv[0] == "claude"`, so the
	///   executable path alone (`.../claude/versions/2.1.245`) is not a reliable marker
	/// - an npm install runs `node .../@anthropic-ai/claude-code/cli.js`, putting the marker one
	///   argument in
	///
	/// Only the first two arguments are considered, which keeps paths that merely mention Claude
	/// (`vim ~/.claude/settings.json`) from matching.
	static func isClaude(arguments: [String]) -> Bool {
		arguments.prefix(2).contains { argument in
			let name = argument.split(separator: "/").last.map(String.init) ?? argument
			return name == "claude" || argument.contains("claude-code")
		}
	}

	/// Every process in a process group, leader first when it is still alive.
	static func processes(inGroup group: pid_t) -> [pid_t] {
		guard group > 0 else {
			return []
		}

		let byteCount = proc_listpids(UInt32(PROC_PGRP_ONLY), UInt32(group), nil, 0)
		guard byteCount > 0 else {
			return []
		}

		// Room for a few more than were counted: the group can grow between the two calls.
		var pids = [pid_t](repeating: 0, count: Int(byteCount) / MemoryLayout<pid_t>.size + 8)
		let filled = proc_listpids(
			UInt32(PROC_PGRP_ONLY),
			UInt32(group),
			&pids,
			Int32(pids.count * MemoryLayout<pid_t>.size)
		)
		guard filled > 0 else {
			return []
		}

		let members = pids.prefix(Int(filled) / MemoryLayout<pid_t>.size).filter { $0 > 0 }
		return members.contains(group) ? [group] + members.filter { $0 != group } : Array(members)
	}

	/// Reads a process's argument vector via `KERN_PROCARGS2`.
	///
	/// The buffer holds a 32-bit `argc`, the executable path, then `argc` NUL-terminated arguments
	/// (with runs of padding NULs in between).
	static func arguments(ofProcess pid: pid_t) -> [String]? {
		var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
		var size = 0
		guard
			sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0,
			size > MemoryLayout<Int32>.size
		else {
			return nil
		}

		var buffer = [UInt8](repeating: 0, count: size)
		guard sysctl(&mib, UInt32(mib.count), &buffer, &size, nil, 0) == 0 else {
			return nil
		}

		let argumentCount = Int(buffer.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) })
		guard argumentCount > 0 else {
			return nil
		}

		var index = MemoryLayout<Int32>.size
		func nextString() -> String? {
			while index < size, buffer[index] == 0 {
				index += 1
			}
			guard index < size else {
				return nil
			}

			let start = index
			while index < size, buffer[index] != 0 {
				index += 1
			}
			return String(decoding: buffer[start ..< index], as: UTF8.self)
		}

		_ = nextString() // executable path, which precedes argv
		return (0 ..< argumentCount).compactMap { _ in nextString() }
	}
}
