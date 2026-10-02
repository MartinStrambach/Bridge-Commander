/// How the built-in terminal decides whether Claude Code in a tab is working or waiting for the
/// user — the status dot and the "Claude is waiting" notification. Mapped onto TerminalFeature's
/// `ClaudeStatusSource` by RepositoryFeature, so neither package depends on the other.
public nonisolated enum ClaudeStatusDetection: String, CaseIterable, Equatable, Sendable {
	case progressAndScreen
	case progressOnly
	case screenOnly

	public static let `default` = Self.progressAndScreen

	public var displayName: String {
		switch self {
		case .progressAndScreen:
			"Progress reports + screen"
		case .progressOnly:
			"Progress reports only"
		case .screenOnly:
			"Screen only"
		}
	}

	public var explanation: String {
		switch self {
		case .progressAndScreen:
			"Claude reports when it starts and finishes working; the screen fills in the rest. Also works with Claude over ssh, inside tmux, or with its progress bar turned off."
		case .progressOnly:
			"Claude counts as waiting whenever it isn't working, so no prompt has to be found on screen. Permission dialogs are still read off the screen. Needs Claude's terminal progress bar (on by default in /config): without it, the tab always shows waiting."
		case .screenOnly:
			"Looks for Claude's prompt once the tab goes quiet, as before progress reports were used. A pause while Claude works can show the tab as waiting until you type."
		}
	}
}
