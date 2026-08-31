import ComposableArchitecture
import Foundation
import GitActionsMenu
import GitCore
import Testing
import ToolsIntegration
@testable import RepositoryFeature

// The terminal header's Git Actions menu is a copy of the opened row's menu state.
// Covers the three legs that keep the copy honest: it is taken when a repo is selected,
// its finished operations re-run the row's status fetch, and the row's status fetch
// feeds the gating fields back into the copy so menu items don't show based on stale counts.
@Suite("Terminal header git actions menu")
@MainActor
struct TerminalGitActionsMenuTests {
	// MARK: - Sync on selection

	@Test("selecting a repo copies the row's git menu into the header")
	func selectRepoCopiesRowMenu() async {
		let store = makeStore()
		store.exhaustivity = .off

		await store.send(.didScanGroup(rootPath: "/repos/alpha", rows: [
			mainRepo("/repos/alpha", name: "alpha"),
		]))
		await store.send(.terminalLayout(.selectRepo(repositoryPath: "/repos/alpha")))

		let rowMenu = store.state.repositoryGroups[id: "/repos/alpha"]?.header.gitActionsMenu
		#expect(rowMenu != nil)
		#expect(store.state.terminalLayout?.gitActionsMenu == rowMenu)
	}

	@Test("selecting the home-directory session clears the header git menu")
	func homeDirectorySelectionClearsMenu() async {
		let store = makeStore()
		store.exhaustivity = .off

		await store.send(.didScanGroup(rootPath: "/repos/alpha", rows: [
			mainRepo("/repos/alpha", name: "alpha"),
		]))
		await store.send(.terminalLayout(.selectRepo(repositoryPath: "/repos/alpha")))
		#expect(store.state.terminalLayout?.gitActionsMenu != nil)

		await store.send(.terminalLayout(.selectRepo(repositoryPath: NSHomeDirectory())))
		#expect(store.state.terminalLayout?.gitActionsMenu == nil)
	}

	// MARK: - Completion routing

	@Test("a finished git operation in the header refreshes the opened repo's row")
	func menuCompletionRefreshesActiveRow() async {
		let store = makeStore()
		store.exhaustivity = .off

		await store.send(.didScanGroup(rootPath: "/repos/alpha", rows: [
			mainRepo("/repos/alpha", name: "alpha"),
		]))
		await store.send(.terminalLayout(.selectRepo(repositoryPath: "/repos/alpha")))

		await store.send(.terminalLayout(.gitActionsMenu(
			.fetchButton(.fetchCompleted(result: nil, error: nil))
		)))

		// Same routing the row's own menu gets: the completion re-runs the row's status fetch.
		await store.receive { isHeaderRefresh($0, groupId: "/repos/alpha") }
		await store.finish()
	}

	@Test("non-completion menu actions in the header do not refresh the row")
	func nonCompletionMenuActionDoesNotRefresh() async {
		let store = makeStore()
		store.exhaustivity = .off

		await store.send(.didScanGroup(rootPath: "/repos/alpha", rows: [
			mainRepo("/repos/alpha", name: "alpha"),
		]))
		await store.send(.terminalLayout(.selectRepo(repositoryPath: "/repos/alpha")))
		store.exhaustivity = .on

		// Exhaustive: a row refresh — or any other emission — fails here. The stash status
		// answer is the menu action closest to a completion without being one.
		await store.send(.terminalLayout(.gitActionsMenu(
			.stashButton(.didCheckStashStatus(hasStash: false))
		)))
		await store.finish()
	}

	// MARK: - Re-sync on row status fetch

	@Test("the opened repo's status fetch re-syncs the header menu's gating fields")
	func statusFetchResyncsHeaderMenu() async {
		let store = makeStore()
		store.exhaustivity = .off

		await store.send(.didScanGroup(rootPath: "/repos/alpha", rows: [
			mainRepo("/repos/alpha", name: "alpha"),
		]))
		await store.send(.terminalLayout(.selectRepo(repositoryPath: "/repos/alpha")))
		#expect(store.state.terminalLayout?.gitActionsMenu?.hasRemoteBranch == false)
		#expect(store.state.terminalLayout?.gitActionsMenu?.unpushedCommitsCount == 0)

		// A remote-tracking branch 3 ahead, with one tracked change and one untracked file.
		let porcelain = """
		# branch.head master
		# branch.upstream origin/master
		# branch.ab +3 -1
		1 .M N... 100644 100644 100644 abc1234 def5678 Sources/App.swift
		? Untracked.swift
		"""
		await store.send(.repositoryGroups(.element(
			id: "/repos/alpha",
			action: .header(.didFetchStatus(GitPorcelainStatus(parsing: porcelain), false))
		)))

		// The stash-list state is internal to the menu, so the copy re-checks it itself.
		await store.receive(\.terminalLayout.gitActionsMenu.refresh)

		let menu = store.state.terminalLayout?.gitActionsMenu
		#expect(menu?.currentBranch == "master")
		#expect(menu?.hasRemoteBranch == true)
		#expect(menu?.unpushedCommitsCount == 3)
		#expect(menu?.stashButton.hasChanges == true)
		#expect(menu?.discardButton.hasTrackedChanges == true)
		#expect(menu?.discardButton.hasUntrackedFiles == true)
		await store.finish()
	}

	@Test("a worktree's status fetch re-syncs the header menu the same way")
	func worktreeStatusFetchResyncsHeaderMenu() async {
		let store = makeStore()
		store.exhaustivity = .off

		await store.send(.didScanGroup(rootPath: "/repos/alpha", rows: [
			mainRepo("/repos/alpha", name: "alpha"),
			worktree("/repos/alpha-one", name: "alpha-one", branch: "feature-one"),
		]))
		await store.send(.terminalLayout(.selectRepo(repositoryPath: "/repos/alpha-one")))
		#expect(store.state.terminalLayout?.gitActionsMenu?.hasRemoteBranch == false)

		let porcelain = """
		# branch.head feature-one
		# branch.upstream origin/feature-one
		# branch.ab +2 -0
		"""
		await store.send(.repositoryGroups(.element(
			id: "/repos/alpha",
			action: .worktrees(.element(
				id: "/repos/alpha-one",
				action: .didFetchStatus(GitPorcelainStatus(parsing: porcelain), false)
			))
		)))

		await store.receive(\.terminalLayout.gitActionsMenu.refresh)

		let menu = store.state.terminalLayout?.gitActionsMenu
		#expect(menu?.currentBranch == "feature-one")
		#expect(menu?.hasRemoteBranch == true)
		#expect(menu?.unpushedCommitsCount == 2)
		#expect(menu?.stashButton.hasChanges == false)
		await store.finish()
	}

	@Test("the header menu's merge flag follows the row's just-reported merge status")
	func statusFetchSyncsHeaderMenuMergeFlag() async {
		let store = makeStore()
		store.exhaustivity = .off

		await store.send(.didScanGroup(rootPath: "/repos/alpha", rows: [
			mainRepo("/repos/alpha", name: "alpha"),
		]))
		await store.send(.terminalLayout(.selectRepo(repositoryPath: "/repos/alpha")))
		#expect(store.state.terminalLayout?.gitActionsMenu?.isMergeInProgress == false)

		// Unlike the other gating fields — set by the row reducer before it reports the status
		// — the merge flag is set by the row's *menu* while handling this very action. The copy
		// still sees it because `forEach` runs the row before the parent; a sync moved ahead of
		// the child (or a merge probe of its own) would lag a refresh behind and fail here.
		await store.send(.repositoryGroups(.element(
			id: "/repos/alpha",
			action: .header(.gitActionsMenu(.didCheckGitStatus(isMergeInProgress: true)))
		)))

		#expect(store.state.terminalLayout?.gitActionsMenu?.isMergeInProgress == true)

		// And back: the terminal's merge banner renders from this copy, so the flag clearing
		// (Finish Merge completion or the menu's own polling) must reach it the same way.
		await store.send(.repositoryGroups(.element(
			id: "/repos/alpha",
			action: .header(.gitActionsMenu(.didCheckGitStatus(isMergeInProgress: false)))
		)))

		#expect(store.state.terminalLayout?.gitActionsMenu?.isMergeInProgress == false)
		await store.finish()
	}

	@Test("another row's status fetch leaves the header menu alone")
	func otherRowStatusFetchIsIgnored() async {
		let store = makeStore()
		store.exhaustivity = .off

		await store.send(.didScanGroup(rootPath: "/repos/alpha", rows: [
			mainRepo("/repos/alpha", name: "alpha"),
		]))
		await store.send(.didScanGroup(rootPath: "/repos/beta", rows: [
			mainRepo("/repos/beta", name: "beta"),
		]))
		await store.send(.terminalLayout(.selectRepo(repositoryPath: "/repos/alpha")))
		store.exhaustivity = .on

		// Exhaustive: the stash re-check sent for the opened repo's own fetches — or any
		// field copy — failing to be guarded on the acting row shows up here. This is the
		// path every row hits on each periodic refresh, so it must stay a no-op.
		await store.send(.repositoryGroups(.element(
			id: "/repos/beta",
			action: .header(.gitActionsMenu(.didCheckGitStatus(isMergeInProgress: false)))
		)))
		await store.finish()
	}

	// MARK: - Helpers

	private func makeStore() -> TestStoreOf<RepositoryListReducer> {
		var initialState = RepositoryListReducer.State()
		initialState.terminalLayout = TerminalLayoutReducer.State()
		return TestStore(initialState: initialState) {
			RepositoryListReducer()
		} withDependencies: {
			// The debounced re-sort scheduled after each YouTrack answer needs a clock.
			$0.continuousClock = ImmediateClock()
			// A row refresh fans out to git, Xcode and PR lookups of its own. Only the
			// header-menu plumbing is under test, so stub the leaves: a failed status
			// short-circuits the row's follow-up fetches, and a missing origin remote
			// short-circuits the pull request lookup on feature branches.
			$0[GitClient.self].getCurrentBranch = { _ in
				GitPorcelainStatus(parsing: "", didSucceed: false)
			}
			$0[GitClient.self].getOriginRemote = { _ in nil }
			$0[XcodeClient.self].findXcodeProject = { _, _, _ in nil }
			$0[LastOpenedDirectoryClient.self].load = { nil }
		}
	}

	private func mainRepo(_ path: String, name: String) -> ScannedRepository {
		ScannedRepository(
			path: path,
			name: name,
			directory: path,
			isWorktree: false,
			branchName: "master"
		)
	}

	private func worktree(_ path: String, name: String, branch: String) -> ScannedRepository {
		ScannedRepository(
			path: path,
			name: name,
			directory: path,
			isWorktree: true,
			branchName: branch
		)
	}

	private func isHeaderRefresh(
		_ action: RepositoryListReducer.Action,
		groupId: String
	) -> Bool {
		guard case let .repositoryGroups(.element(id: id, action: .header(.refresh))) = action else {
			return false
		}
		return id == groupId
	}
}
