import ComposableArchitecture
import Foundation
import GitActionsMenu
import GitCore
import Testing
import ToolsIntegration
@testable import RepositoryFeature

// The terminal toolbar's Git Actions menu is the opened row's own menu: the toolbar scopes the
// row's store and keeps no copy. What the toolbar shows is therefore whatever the row's status
// fetch leaves in the row's menu, for a main repository and for a worktree alike.
@Suite("Terminal toolbar git actions menu")
@MainActor
struct TerminalGitActionsMenuTests {
	@Test("the opened repo's status fetch updates the gating fields of the menu the toolbar shows")
	func statusFetchUpdatesOpenedRowMenu() async {
		let store = makeStore()
		store.exhaustivity = .off

		await store.send(.didScanGroup(rootPath: "/repos/alpha", rows: [
			mainRepo("/repos/alpha", name: "alpha"),
		]))
		await open("/repos/alpha", in: store)
		#expect(headerMenu(in: store)?.hasRemoteBranch == false)
		#expect(headerMenu(in: store)?.unpushedCommitsCount == 0)

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

		let menu = headerMenu(in: store)
		#expect(menu?.currentBranch == "master")
		#expect(menu?.hasRemoteBranch == true)
		#expect(menu?.unpushedCommitsCount == 3)
		#expect(menu?.stashButton.hasChanges == true)
		#expect(menu?.discardButton.hasTrackedChanges == true)
		#expect(menu?.discardButton.hasUntrackedFiles == true)
		await store.finish()
	}

	@Test("an opened worktree's status fetch updates its menu the same way")
	func worktreeStatusFetchUpdatesOpenedRowMenu() async {
		let store = makeStore()
		store.exhaustivity = .off

		await store.send(.didScanGroup(rootPath: "/repos/alpha", rows: [
			mainRepo("/repos/alpha", name: "alpha"),
			worktree("/repos/alpha-one", name: "alpha-one", branch: "feature-one"),
		]))
		await open("/repos/alpha-one", in: store)
		#expect(worktreeMenu(in: store)?.hasRemoteBranch == false)

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

		let menu = worktreeMenu(in: store)
		#expect(menu?.currentBranch == "feature-one")
		#expect(menu?.hasRemoteBranch == true)
		#expect(menu?.unpushedCommitsCount == 2)
		#expect(menu?.stashButton.hasChanges == false)
		await store.finish()
	}

	// MARK: - Helpers

	/// Opens the repository's first terminal, which puts the panel and its toolbar on screen.
	private func open(_ path: String, in store: TestStoreOf<RepositoryListReducer>) async {
		await store.send(.terminals(.selectRepo(repositoryPath: path)))
		await store.receive(\.terminals.sessionBuilt)
		#expect(store.state.terminals.activeRepositoryPath == path)
		#expect(store.state.terminalLayout != nil)
	}

	private func headerMenu(in store: TestStoreOf<RepositoryListReducer>) -> GitActionsMenuReducer.State? {
		store.state.repositoryGroups[id: "/repos/alpha"]?.header.gitActionsMenu
	}

	private func worktreeMenu(in store: TestStoreOf<RepositoryListReducer>) -> GitActionsMenuReducer.State? {
		store.state.repositoryGroups[id: "/repos/alpha"]?.worktrees[id: "/repos/alpha-one"]?.gitActionsMenu
	}

	private func makeStore() -> TestStoreOf<RepositoryListReducer> {
		TestStore(initialState: RepositoryListReducer.State()) {
			RepositoryListReducer()
		} withDependencies: {
			$0.uuid = .incrementing
			// The debounced re-sort scheduled after each YouTrack answer needs a clock.
			$0.continuousClock = ImmediateClock()
			// A row refresh fans out to git, Xcode and PR lookups of its own. Only the
			// menu plumbing is under test, so stub the leaves: a failed status
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
}
