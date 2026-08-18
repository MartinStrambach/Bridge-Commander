import ComposableArchitecture
import GitCore
import Settings
import TerminalFeature
import Testing
import ToolsIntegration
@testable import RepositoryFeature

// The header toggle passes `livePaths` into `rowVisibility(query:livePaths:)`: `nil` when the filter
// is off, otherwise the set of repository paths that have a live terminal session. A row shows only
// when it satisfies both that filter and the branch query. The group's own row is the section
// header, so it renders whenever the group renders — a group disappears only when neither it nor any
// of its worktrees has a terminal.
@Suite("Repository list active-terminal filter")
@MainActor
struct RepositoryListTerminalFilterTests {
	@Test("no live paths means the filter is off and every row shows")
	func nilLivePathsLeavesRowsUnfiltered() {
		#expect(group().rowVisibility(query: "", livePaths: nil) == .unfiltered)
	}

	@Test("a group with no live terminal anywhere is hidden")
	func groupWithoutTerminalsIsHidden() {
		#expect(group().rowVisibility(query: "", livePaths: []) == .hidden)
		// A live terminal in some *other* repo must not rescue this group.
		#expect(group().rowVisibility(query: "", livePaths: ["/repos/elsewhere"]) == .hidden)
	}

	@Test("an empty query still filters when the toggle is on")
	func emptyQueryStillAppliesTerminalFilter() {
		// Guards the `query.isEmpty` short-circuit: it must not swallow the terminal predicate.
		let visibility = group().rowVisibility(query: "", livePaths: ["/repos/alpha-fix"])

		#expect(visibility == .worktrees(["/repos/alpha-fix"]))
		#expect(visibility != .unfiltered)
	}

	@Test("a live worktree shows while its dead siblings and header do not")
	func liveWorktreeHidesDeadSiblings() {
		let visibility = group().rowVisibility(query: "", livePaths: ["/repos/alpha-fix"])

		#expect(visibility.includesWorktree(id: "/repos/alpha-fix"))
		#expect(!visibility.includesWorktree(id: "/repos/alpha-other"))
	}

	@Test("a live header with no live worktrees keeps the group but reveals no worktrees")
	func liveHeaderRevealsNoWorktrees() {
		let visibility = group().rowVisibility(query: "", livePaths: ["/repos/alpha"])

		#expect(visibility == .worktrees([]))
		#expect(!visibility.isHidden)
		#expect(!visibility.includesWorktree(id: "/repos/alpha-fix"))
	}

	@Test("the header row stays visible when only a worktree has a terminal")
	func headerSurvivesWorktreeOnlyMatch() {
		// `.worktrees` is never `.hidden`, so RepoGroupView still renders the section — and with it
		// the group's own row as the section header. That is the agreed behaviour.
		#expect(!group().rowVisibility(query: "", livePaths: ["/repos/alpha-fix"]).isHidden)
	}

	@Test("every live worktree shows when several have terminals")
	func multipleLiveWorktreesAllShow() {
		let visibility = group().rowVisibility(
			query: "",
			livePaths: ["/repos/alpha-fix", "/repos/alpha-other"]
		)

		#expect(visibility == .worktrees(["/repos/alpha-fix", "/repos/alpha-other"]))
	}

	// MARK: - Composing with the branch query

	@Test("query and terminal filter compose with AND")
	func filtersComposeWithAnd() {
		// alpha-fix matches the query and is live — the only row that satisfies both.
		#expect(
			group().rowVisibility(query: "MOB", livePaths: ["/repos/alpha-fix"])
				== .worktrees(["/repos/alpha-fix"])
		)
		// alpha-other is live but does not match the query.
		#expect(
			group().rowVisibility(query: "MOB-123", livePaths: ["/repos/alpha-other"])
				== .hidden
		)
		// alpha-release matches the query but has no terminal.
		#expect(
			group().rowVisibility(query: "release", livePaths: ["/repos/alpha-fix"])
				== .hidden
		)
	}

	@Test("a header matching both filters survives a query that excludes every worktree")
	func headerMatchesBothFilters() {
		#expect(
			group().rowVisibility(query: "master", livePaths: ["/repos/alpha"]) == .worktrees([])
		)
		// Same query, but the header has no terminal.
		#expect(
			group().rowVisibility(query: "master", livePaths: ["/repos/alpha-fix"]) == .hidden
		)
	}

	// MARK: - Session liveness

	@Test("only sessions with a usable terminal count as live")
	func failedSessionsAreNotLive() {
		#expect(TerminalSessionStatus.active.isLive)
		#expect(TerminalSessionStatus.launching.isLive)
		#expect(TerminalSessionStatus.waitingForInput.isLive)
		// `.failed` lingers in state after the shell exits but shows no dot and has no attached
		// view, so the list must treat it as "no terminal".
		#expect(!TerminalSessionStatus.failed("exited (1)").isLive)
	}

	// MARK: - Toggle wiring

	@Test("the toggle flips the flag without touching the stored groups")
	func toggleLeavesGroupsUntouched() async {
		let store = TestStore(initialState: RepositoryListReducer.State()) {
			RepositoryListReducer()
		} withDependencies: {
			$0[GitClient.self].getCurrentBranch = { _ in
				GitPorcelainStatus(parsing: "", didSucceed: false)
			}
			$0[XcodeClient.self].findXcodeProject = { _, _, _ in nil }
			$0[LastOpenedDirectoryClient.self].load = { nil }
		}
		store.exhaustivity = .off

		await store.send(.didScanGroup(rootPath: "/repos/alpha", rows: [
			scanned("/repos/alpha", name: "alpha", branch: "master", isWorktree: false),
			scanned("/repos/alpha-fix", name: "alpha-fix", branch: "MOB-123_fix", isWorktree: true),
		]))
		let before = store.state.repositoryGroups
		#expect(!store.state.showsActiveTerminalsOnly)

		await store.send(.view(.activeTerminalFilterChanged(true)))
		#expect(store.state.showsActiveTerminalsOnly)
		// The list scopes into these, so the toggle must not churn their identity or contents.
		#expect(store.state.repositoryGroups == before)

		// Re-sending the same value is a no-op, so a Binding that re-sets it cannot desync.
		await store.send(.view(.activeTerminalFilterChanged(true)))
		#expect(store.state.showsActiveTerminalsOnly)

		await store.send(.view(.activeTerminalFilterChanged(false)))
		#expect(!store.state.showsActiveTerminalsOnly)
		#expect(store.state.repositoryGroups == before)
	}

	// MARK: - Helpers

	/// One `master` group with three worktrees, none of which share a branch prefix by accident:
	/// two `MOB-*` and one `release-1`.
	private func group() -> RepoGroupReducer.State {
		RepoGroupReducer.State(
			id: "/repos/alpha",
			isCollapsed: false,
			header: row("/repos/alpha", name: "alpha", branch: "master", isWorktree: false),
			worktrees: [
				row("/repos/alpha-fix", name: "alpha-fix", branch: "MOB-123_fix"),
				row("/repos/alpha-other", name: "alpha-other", branch: "MOB-999_other"),
				row("/repos/alpha-release", name: "alpha-release", branch: "release-1"),
			],
			settings: RepoGroupSettings()
		)
	}

	private func row(
		_ path: String,
		name: String,
		branch: String,
		isWorktree: Bool = true
	) -> RepositoryRowReducer.State {
		RepositoryRowReducer.State(
			path: path,
			name: name,
			branchName: branch,
			isWorktree: isWorktree
		)
	}

	private func scanned(
		_ path: String,
		name: String,
		branch: String,
		isWorktree: Bool
	) -> ScannedRepository {
		ScannedRepository(
			path: path,
			name: name,
			directory: path,
			isWorktree: isWorktree,
			branchName: branch,
			isMergeInProgress: false
		)
	}
}
