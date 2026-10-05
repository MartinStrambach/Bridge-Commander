/// What happens once the create-worktree dialog has made the worktree.
public nonisolated enum WorktreeCreationFollowUp: String, CaseIterable, Equatable, Sendable {
	/// Just add the worktree to the list.
	case nothing
	/// Open it in the built-in terminal, which runs the group's usual startup command.
	case openTerminal
	/// Open it in the built-in terminal running Claude Code instead of that command.
	case runClaude

	public var title: String {
		switch self {
		case .nothing: "Nothing"
		case .openTerminal: "Open Terminal"
		case .runClaude: "Run Claude"
		}
	}
}
