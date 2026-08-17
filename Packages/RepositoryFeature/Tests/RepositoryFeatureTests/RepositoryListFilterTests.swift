import ComposableArchitecture
import GitCore
import Testing
import ToolsIntegration
@testable import RepositoryFeature

// `searchVisibility(query:)` backs the "Filter by branch name…" field: the list scopes into the
// stored groups and asks each one what the query reveals, so filtering never rebuilds group state.
// Filtering is row-level — a group shows only when its own branch or one of its worktrees matches,
// and only the matching worktrees show. The header row always renders (it is the section header),
// so a header-only match leaves a visible group with no visible worktrees.
@Suite("Repository list branch filter")
@MainActor
struct RepositoryListFilterTests {
	@Test("an empty query reveals every row of every group")
	func emptyQueryRevealsEverything() async {
		let store = await makeStore()

		#expect(store.state.searchText.isEmpty)
		#expect(visibility(store) == [
			"/repos/alpha": .unfiltered,
			"/repos/beta": .unfiltered,
		])
		// `.unfiltered` reveals rows without the caller having to enumerate ids.
		#expect(BranchSearchVisibility.unfiltered.includesWorktree(id: "/repos/anything"))
	}

	@Test("a worktree match hides the group's non-matching worktrees")
	func worktreeMatchHidesSiblings() async {
		let store = await makeStore()

		await store.send(.view(.searchTextChanged("MOB-123")))

		#expect(visibility(store) == [
			"/repos/alpha": .worktrees(["/repos/alpha-fix"]),
			"/repos/beta": .hidden,
		])
	}

	@Test("a query matching nothing hides every group")
	func nonMatchingQueryHidesEverything() async {
		let store = await makeStore()

		await store.send(.view(.searchTextChanged("no-such-branch")))

		#expect(visibility(store) == [
			"/repos/alpha": .hidden,
			"/repos/beta": .hidden,
		])
	}

	@Test("a header-only match keeps the group but reveals no worktrees")
	func headerMatchRevealsNoWorktrees() async {
		let store = await makeStore()

		// "master" is the main repo's branch in both groups and no worktree's branch.
		await store.send(.view(.searchTextChanged("master")))

		#expect(visibility(store) == [
			"/repos/alpha": .worktrees([]),
			"/repos/beta": .worktrees([]),
		])
		#expect(!BranchSearchVisibility.worktrees([]).includesWorktree(id: "/repos/alpha-fix"))
	}

	@Test("matching is case-insensitive and matches on substrings")
	func matchingIsCaseInsensitiveSubstring() async {
		let store = await makeStore()

		await store.send(.view(.searchTextChanged("mob-9")))

		#expect(visibility(store) == [
			"/repos/alpha": .worktrees(["/repos/alpha-other"]),
			"/repos/beta": .hidden,
		])
	}

	@Test("a match in one group does not reveal another group's worktrees")
	func matchesAreScopedPerGroup() async {
		let store = await makeStore()

		// "release" appears once in each group, alongside worktrees that must not come along.
		await store.send(.view(.searchTextChanged("release")))

		#expect(visibility(store) == [
			"/repos/alpha": .worktrees(["/repos/alpha-release"]),
			"/repos/beta": .worktrees(["/repos/beta-release"]),
		])
	}

	@Test("filtering leaves the stored groups untouched")
	func filteringDoesNotRebuildGroupState() async {
		let store = await makeStore()
		let before = store.state.repositoryGroups

		await store.send(.view(.searchTextChanged("MOB-123")))
		_ = visibility(store)

		// The list scopes into these, so a query must not churn their identity or contents —
		// that is what made every keystroke re-render (and re-filter) the whole list.
		#expect(store.state.repositoryGroups == before)
	}

	// MARK: - Helpers

	/// What the list would render for the current query, keyed by group id.
	private func visibility(
		_ store: TestStoreOf<RepositoryListReducer>
	) -> [String: BranchSearchVisibility] {
		let query = store.state.searchText
		return Dictionary(
			uniqueKeysWithValues: store.state.repositoryGroups.map {
				($0.id, $0.searchVisibility(query: query))
			}
		)
	}

	/// Two groups, both with a `master` main repo. Alpha carries the MOB-* worktrees; each group
	/// has its own `release-*` worktree so per-group scoping is observable.
	private func makeStore() async -> TestStoreOf<RepositoryListReducer> {
		let store = TestStore(initialState: RepositoryListReducer.State()) {
			RepositoryListReducer()
		} withDependencies: {
			// Rows fan out to git and Xcode lookups of their own. Only the parent's filtering is
			// under test, so stub the leaves: a failed status short-circuits the row's follow-ups.
			$0[GitClient.self].getCurrentBranch = { _ in
				GitPorcelainStatus(parsing: "", didSucceed: false)
			}
			$0[XcodeClient.self].findXcodeProject = { _, _, _ in nil }
			$0[LastOpenedDirectoryClient.self].load = { nil }
		}
		store.exhaustivity = .off

		await store.send(.didScanGroup(rootPath: "/repos/alpha", rows: [
			mainRepo("/repos/alpha", name: "alpha"),
			worktree("/repos/alpha-fix", name: "alpha-fix", branch: "MOB-123_fix"),
			worktree("/repos/alpha-other", name: "alpha-other", branch: "MOB-999_other"),
			worktree("/repos/alpha-release", name: "alpha-release", branch: "release-1"),
		]))
		await store.send(.didScanGroup(rootPath: "/repos/beta", rows: [
			mainRepo("/repos/beta", name: "beta"),
			worktree("/repos/beta-cleanup", name: "beta-cleanup", branch: "cleanup"),
			worktree("/repos/beta-release", name: "beta-release", branch: "release-2"),
		]))

		return store
	}

	private func mainRepo(_ path: String, name: String) -> ScannedRepository {
		ScannedRepository(
			path: path,
			name: name,
			directory: path,
			isWorktree: false,
			branchName: "master",
			isMergeInProgress: false
		)
	}

	private func worktree(_ path: String, name: String, branch: String) -> ScannedRepository {
		ScannedRepository(
			path: path,
			name: name,
			directory: path,
			isWorktree: true,
			branchName: branch,
			isMergeInProgress: false
		)
	}
}
