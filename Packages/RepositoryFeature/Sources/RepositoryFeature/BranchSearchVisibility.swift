import ComposableArchitecture

/// What a branch-name query reveals inside one repo group.
///
/// The list scopes its `ForEach` into the *stored* groups and asks each group what to reveal, so a
/// keystroke never rebuilds group state. Deriving a filtered copy of the groups instead — however
/// briefly — is a trap: the scoped child stores re-read the derived value on every state access
/// (~100 evaluations per render pass), and rewriting each group's worktrees per keystroke
/// re-renders every row in the list.
enum BranchSearchVisibility: Equatable {
	/// No active query — every row shows.
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
	/// Resolves `query` against this group's own branch and its worktrees' branches.
	///
	/// Cheap by design — it touches only this group's rows, and the empty-query case allocates
	/// nothing. See ``BranchSearchVisibility`` for why the result is computed per group at render
	/// time rather than stored as a filtered copy of the list.
	func searchVisibility(query: String) -> BranchSearchVisibility {
		guard !query.isEmpty else {
			return .unfiltered
		}

		let matching = worktrees.lazy
			.filter { $0.branchName?.localizedCaseInsensitiveContains(query) == true }
			.map(\.id)
		let ids = Set(matching)
		guard ids.isEmpty else {
			return .worktrees(ids)
		}
		return header.branchName?.localizedCaseInsensitiveContains(query) == true
			? .worktrees([])
			: .hidden
	}
}
