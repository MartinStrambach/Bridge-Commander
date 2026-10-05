/// Where the create-worktree dialog takes the new worktree's branch from — its tabs.
public nonisolated enum WorktreeSource: String, CaseIterable, Codable, Equatable, Sendable {
	/// A typed branch name off a base branch, or an existing branch checked out as is.
	case branch
	/// A new branch named after a YouTrack ticket, off a base branch.
	case ticket
	/// An open PR/MR's own branch, checked out as is.
	case pullRequest

	public var title: String {
		switch self {
		case .branch: "Branch"
		case .ticket: "Ticket"
		case .pullRequest: "PR / MR"
		}
	}
}
