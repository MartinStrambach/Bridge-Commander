import SwiftTerm

/// The environment each pane's shell starts with.
enum TerminalEnvironment {
	/// SwiftTerm's defaults plus `ConEmuANSI=ON`, which makes Claude Code report its progress.
	///
	/// Claude Code sends OSC 9;4 progress (`9;4;3` while a turn runs, `9;4;0` when it is done)
	/// only to terminals it recognises as drawing a progress bar: Ghostty 1.2+, iTerm2 3.6.6+, or
	/// ConEmu, detected by `ConEmuANSI`/`ConEmuPID`/`ConEmuTask` (checked in Claude Code
	/// 2.1.283). That report is the only direct word from Claude on whether it is working, and
	/// `ClaudeStatusDetector` relies on it to stop reading Claude's always-visible input box as
	/// "waiting" mid-turn. ConEmu is claimed rather than Ghostty or iTerm2 because nothing else
	/// in Claude Code acts on it: Ghostty and iTerm2 also change its notification channel and
	/// keyboard handling, while "conemu" only feeds telemetry.
	static func variables() -> [String] {
		Terminal.getEnvironmentVariables(termName: "xterm-256color") + ["ConEmuANSI=ON"]
	}
}
