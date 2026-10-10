import ComposableArchitecture
import Foundation
import GitActionsMenu
import GitCore
import Testing
import ToolsIntegration
@testable import RepositoryFeature

// The terminal toolbar's Git Actions menu, Push button and merge banner act on the opened row's own
// state. The menu used to be a copy held in `TerminalLayoutReducer.State` (and Push and Finish Merge
// ran there too): hiding the panel nils that state, so `ifLet` cancelled a running push, pull or
// checkout, SIGTERMing git with no error shown; and switching repositories replaced the copy, so
// the operation finished into the next repository's copy while its own row never showed it running.
@Suite("Terminal toolbar git actions act on the opened row")
@MainActor
struct TerminalGitActionsMenuTests {
	// MARK: - Operations belong to the row

	@Test("a git operation keeps running and lands on its row after the terminal is hidden")
	func operationSurvivesHidingTerminal() async {
		let (gate, release) = AsyncStream.makeStream(of: Void.self)
		let store = await makeStoreShowingAlpha {
			$0[GitClient.self].fetch = { _ in
				// Held here until the terminal has been hidden.
				for await _ in gate { break }
				return GitFetchHelper.FetchResult(fetchedBranches: 1, isAlreadyUpToDate: false)
			}
		}

		await store.send(menuAction(.fetchButton(.fetchTapped), on: "/repos/alpha"))
		#expect(menu(of: "/repos/alpha", in: store)?.isOperationRunning == true)

		await store.send(.terminalLayout(.hideTerminalMode))
		#expect(store.state.terminalLayout == nil)
		#expect(menu(of: "/repos/alpha", in: store)?.isOperationRunning == true)

		release.yield()
		await store.receive(\.repositoryGroups[id: "/repos/alpha"].header.gitActionsMenu.fetchButton.fetchCompleted)
		await store.receive { isHeaderRefresh($0, groupId: "/repos/alpha") }
		#expect(menu(of: "/repos/alpha", in: store)?.isOperationRunning == false)
		await store.finish()
	}

	@Test("a git operation stays with its repository when the panel switches to another")
	func operationStaysWithItsRepository() async {
		let (gate, release) = AsyncStream.makeStream(of: Void.self)
		let store = await makeStoreShowingAlpha {
			$0[GitClient.self].fetch = { _ in
				for await _ in gate { break }
				return GitFetchHelper.FetchResult(fetchedBranches: 1, isAlreadyUpToDate: false)
			}
		}
		store.exhaustivity = .off(showSkippedAssertions: false)

		await store.send(menuAction(.fetchButton(.fetchTapped), on: "/repos/alpha"))
		await store.send(.terminalLayout(.selectRepo(repositoryPath: "/repos/beta")))
		// Alpha's own menu shows the fetch, so it offers no second git write on top of it.
		#expect(menu(of: "/repos/alpha", in: store)?.isOperationRunning == true)
		#expect(menu(of: "/repos/beta", in: store)?.isOperationRunning == false)

		release.yield()
		await store.receive(\.repositoryGroups[id: "/repos/alpha"].header.gitActionsMenu.fetchButton.fetchCompleted)
		// The completion refreshes alpha, the row it ran on, not the one now on screen.
		await store.receive { isHeaderRefresh($0, groupId: "/repos/alpha") }
		#expect(menu(of: "/repos/alpha", in: store)?.isOperationRunning == false)
		await store.finish()
	}

	@Test("the terminal toolbar keeps no git state of its own")
	func terminalLayoutHoldsNoGitCopy() async throws {
		let store = await makeStoreShowingAlpha { _ in }
		let layout = try #require(store.state.terminalLayout)

		let labels = Mirror(reflecting: layout).children.compactMap(\.label)
		#expect(!labels.contains { $0.localizedCaseInsensitiveContains("gitActions") })
		#expect(!labels.contains { $0.localizedCaseInsensitiveContains("push") })
		#expect(!labels.contains { $0.localizedCaseInsensitiveContains("merge") })
	}

	// MARK: - Finish Merge

	@Test("a finished merge refreshes the row it ran on")
	func finishMergeRefreshesRow() async {
		let store = await makeStoreShowingAlpha { _ in }

		await store.send(.repositoryGroups(.element(id: "/repos/alpha", action: .header(.finishMergeCompleted(nil)))))
		await store.receive { isHeaderRefresh($0, groupId: "/repos/alpha") }
		await store.finish()
		#expect(store.state.alert == nil)
	}

	@Test("a failed merge alerts instead of refreshing")
	func finishMergeFailureAlerts() async {
		let store = await makeStoreShowingAlpha { _ in }
		store.exhaustivity = .on

		await store.send(.repositoryGroups(.element(
			id: "/repos/alpha",
			action: .header(.finishMergeCompleted(.mergeFailed("CONFLICT in App.swift")))
		))) {
			$0.alert = AlertState {
				TextState("Finish Merge Failed")
			} message: {
				TextState(GitError.mergeFailed("CONFLICT in App.swift").localizedDescription)
			}
		}
	}

	@Test("a worktree's failed merge alerts the same way")
	func worktreeFinishMergeFailureAlerts() async {
		let store = await makeStoreShowingAlpha { _ in }
		await store.send(.didScanGroup(rootPath: "/repos/alpha", rows: [
			repository("/repos/alpha", isWorktree: false),
			repository("/repos/alpha-one", isWorktree: true),
		]))
		store.exhaustivity = .on

		await store.send(.repositoryGroups(.element(
			id: "/repos/alpha",
			action: .worktrees(.element(
				id: "/repos/alpha-one",
				action: .finishMergeCompleted(.mergeFailed("CONFLICT"))
			))
		))) {
			$0.alert = AlertState {
				TextState("Finish Merge Failed")
			} message: {
				TextState(GitError.mergeFailed("CONFLICT").localizedDescription)
			}
		}
	}

	@Test("Finish Merge does nothing while one is already running")
	func finishMergeIgnoredWhileRunning() async {
		var row = RepositoryRowReducer.State(path: "/repos/alpha", name: "alpha", branchName: "master")
		row.isFinishingMerge = true
		let store = TestStore(initialState: row) {
			RepositoryRowReducer()
		}

		// Exhaustive: a second `git commit --no-edit` starting here fails the test.
		await store.send(.finishMergeTapped)
	}

	@Test("a finish-merge completion stops the spinner whether it succeeded or failed", arguments: [true, false])
	func finishMergeCompletionClearsFlag(failed: Bool) async {
		var row = RepositoryRowReducer.State(path: "/repos/alpha", name: "alpha", branchName: "master")
		row.isFinishingMerge = true
		let store = TestStore(initialState: row) {
			RepositoryRowReducer()
		} withDependencies: {
			// What the refresh after a success asks; a failed status short-circuits the rest.
			$0[GitClient.self].getCurrentBranch = { _ in
				GitPorcelainStatus(parsing: "", didSucceed: false)
			}
			$0[XcodeClient.self].findXcodeProject = { _, _, _ in nil }
		}
		store.exhaustivity = .off

		await store.send(.finishMergeCompleted(failed ? .mergeFailed("conflict") : nil)) {
			$0.isFinishingMerge = false
		}
	}

	// MARK: - Helpers

	private func menuAction(
		_ action: GitActionsMenuReducer.Action,
		on groupId: String
	) -> RepositoryListReducer.Action {
		.repositoryGroups(.element(id: groupId, action: .header(.gitActionsMenu(action))))
	}

	private func menu(
		of groupId: String,
		in store: TestStoreOf<RepositoryListReducer>
	) -> GitActionsMenuReducer.State? {
		store.state.repositoryGroups[id: groupId]?.header.gitActionsMenu
	}

	/// Two scanned repositories, alpha opened in the terminal panel.
	private func makeStoreShowingAlpha(
		_ dependencies: @escaping (inout DependencyValues) -> Void
	) async -> TestStoreOf<RepositoryListReducer> {
		var initialState = RepositoryListReducer.State()
		initialState.terminalLayout = TerminalLayoutReducer.State()
		let store = TestStore(initialState: initialState) {
			RepositoryListReducer()
		} withDependencies: {
			$0.continuousClock = ImmediateClock()
			// A row refresh fans out to git, Xcode and PR lookups of its own: a failed status
			// short-circuits the row's follow-up fetches, and a missing origin remote the PR lookup.
			$0[GitClient.self].getCurrentBranch = { _ in
				GitPorcelainStatus(parsing: "", didSucceed: false)
			}
			$0[GitClient.self].getOriginRemote = { _ in nil }
			$0[XcodeClient.self].findXcodeProject = { _, _, _ in nil }
			$0[LastOpenedDirectoryClient.self].load = { nil }
			dependencies(&$0)
		}
		store.exhaustivity = .off
		await store.send(.didScanGroup(rootPath: "/repos/alpha", rows: [repository("/repos/alpha", isWorktree: false)]))
		await store.send(.didScanGroup(rootPath: "/repos/beta", rows: [repository("/repos/beta", isWorktree: false)]))
		await store.send(.terminalLayout(.selectRepo(repositoryPath: "/repos/alpha")))
		return store
	}

	private func repository(_ path: String, isWorktree: Bool) -> ScannedRepository {
		ScannedRepository(
			path: path,
			name: (path as NSString).lastPathComponent,
			directory: path,
			isWorktree: isWorktree,
			branchName: isWorktree ? "feature-one" : "master"
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
