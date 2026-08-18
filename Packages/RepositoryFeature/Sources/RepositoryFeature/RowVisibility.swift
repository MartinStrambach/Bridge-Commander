import ComposableArchitecture

/// What the list's filters reveal inside one repo group.
///
/// Two filters resolve to this: the branch-name query and the active-terminal toggle. They compose
/// with AND — a row shows only when it satisfies both.
///
/// The list scopes its `ForEach` into the *stored* groups and asks each group what to reveal, so a
/// keystroke never rebuilds group state. Deriving a filtered copy of the groups instead — however
/// briefly — is a trap: the scoped child stores re-read the derived value on every state access
/// (~100 evaluations per render pass), and rewriting each group's worktrees per keystroke
/// re-renders every row in the list.
enum RowVisibility: Equatable {
	/// No active filter — every row shows.
	case unfiltered
	/// The group matched; only these worktrees show. Empty when only the group's own branch
	/// matched: the header row is the section header, so it renders either way.
	case worktrees(Set<String>)
	/// Nothing in the group matched — the group does not render at all.
	case hidden

	var isHidden: Bool {
		self == .hidden
	}

	func includesWorktree(id: String) -> Bool {
		switch self {
		case .unfiltered:
			true
		case let .worktrees(ids):
			ids.contains(id)
		case .hidden:
			false
		}
	}
}

extension RepoGroupReducer.State {
	/// Resolves `query` and the active-terminal filter against this group's own row and its
	/// worktrees.
	///
	/// Cheap by design — it touches only this group's rows, and the unfiltered case allocates
	/// nothing. See ``RowVisibility`` for why the result is computed per group at render time
	/// rather than stored as a filtered copy of the list.
	///
	/// - Parameters:
	///   - query: Branch-name substring to match, case-insensitively. Empty matches every row.
	///   - livePaths: Repository paths that have a live terminal session, or `nil` when the
	///     active-terminal filter is off.
	func rowVisibility(query: String, livePaths: Set<String>? = nil) -> RowVisibility {
		guard !query.isEmpty || livePaths != nil else {
			return .unfiltered
		}

		func matches(_ row: RepositoryRowReducer.State) -> Bool {
			if !query.isEmpty, row.branchName?.localizedCaseInsensitiveContains(query) != true {
				return false
			}
			if let livePaths, !livePaths.contains(row.path) {
				return false
			}
			return true
		}

		let ids = Set(worktrees.lazy.filter(matches).map(\.id))
		guard ids.isEmpty else {
			return .worktrees(ids)
		}
		return matches(header) ? .worktrees([]) : .hidden
	}
}
