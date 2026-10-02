/// What `ClaudeStatusDetector` bases a pane's waiting/active status on. Fixed when the pane is
/// created: whether Claude reports progress at all is decided by the shell's environment, which
/// only exists at launch.
public enum ClaudeStatusSource: Equatable, Sendable {
	/// Claude's progress reports say when a turn is running; the screen decides the rest — dialogs
	/// mid-turn, the prompt once a turn is done, and everything for a Claude that never reports.
	case progressAndScreen
	/// Claude in the foreground and not mid-turn is waiting, with no screen reading. The screen is
	/// still read mid-turn for dialogs (permission prompts), which come while Claude reports work.
	/// A Claude that never reports progress (older versions, the setting turned off, over ssh or
	/// inside tmux) reads as waiting whenever it is in the foreground.
	case progressOnly
	/// The screen alone, as before progress reports were used. Claude is not asked to report.
	case screenOnly

	/// Whether the pane's shell is started so that Claude Code sends progress reports.
	var requestsProgress: Bool {
		self != .screenOnly
	}
}
