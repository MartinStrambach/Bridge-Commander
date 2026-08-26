import Darwin

/// Identifies the process holding the foreground of a pseudo-terminal.
///
/// Used to gate the Claude prompt scan: a `❯` on screen only means "Claude is waiting" when Claude
/// Code actually owns the pane. In a plain shell the same glyph is a prompt theme, a line of command
/// output, or leftover scrollback.
enum PtyForegroundProcess {
	/// Whether Claude Code holds the foreground of the terminal behind `descriptor`.
	///
	/// Returns `nil` when the foreground process can't be identified (closed descriptor, no
	/// controlling process group, or a process this app may not inspect). Callers should fall back to
	/// their own heuristics on `nil` rather than read it as "not Claude", so an unexpected failure
	/// degrades to the previous behaviour instead of dropping the status entirely.
	static func isClaude(ptyDescriptor descriptor: Int32) -> Bool? {
		guard descriptor >= 0 else {
			return nil
		}

		let processGroup = tcgetpgrp(descriptor)
		guard processGroup > 0, let arguments = arguments(ofProcess: processGroup) else {
			return nil
		}

		return isClaude(arguments: arguments)
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

	/// Reads a process's argument vector via `KERN_PROCARGS2`.
	///
	/// The buffer holds a 32-bit `argc`, the executable path, then `argc` NUL-terminated arguments
	/// (with runs of padding NULs in between).
	private static func arguments(ofProcess pid: pid_t) -> [String]? {
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
