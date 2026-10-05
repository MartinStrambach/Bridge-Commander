import Foundation

/// The shell command that starts Claude Code, typed into a built-in terminal tab.
public nonisolated enum ClaudeCommand {
	/// `claude` on its own, or `claude '<prompt>'` with the prompt single-quoted for the shell.
	///
	/// The command is typed into an interactive shell, so the prompt must survive as one argument:
	/// single quotes stop every expansion, and a quote inside the prompt is closed, escaped and
	/// reopened (`'\''`). Line breaks become spaces — typing one would submit the line early.
	public static func make(prompt: String) -> String {
		// `split`, not `components(separatedBy: .newlines)`: the latter sees "\r\n" as two breaks.
		let flattened = prompt
			.split(whereSeparator: \.isNewline)
			.joined(separator: " ")
			.trimmingCharacters(in: .whitespaces)
		guard !flattened.isEmpty else {
			return "claude"
		}
		return "claude '" + flattened.replacingOccurrences(of: "'", with: "'\\''") + "'"
	}
}
