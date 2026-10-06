import ComposableArchitecture
import GitActionsMenu
import GitCore
import StagingFeature
import Testing
import ToolsIntegration
@testable import RepositoryFeature

// What sends a row back to git: first appearance (once), a refresh (every time), each finished
// git-menu operation, closing the staging sheet. And what a row reports up to its group —
// a created or deleted worktree — which is what makes the list rescan.
@Suite("Repository row action routing")
@MainActor
struct RepositoryRowActionRoutingTests {
	// MARK: - Loading

	@Test("the first appearance loads the row; later appearances do not reload it")
	func onAppearLoadsOnce() async {
		let store = makeStore()

		await store.send(.onAppear) {
			$0.isLoaded = true
		}
		await store.receive(\.gitActionsMenu.onAppear)
		await store.receive(\.xcodeButton.onAppear)
		await store.receive(\.didFetchStatus)
		await store.finish()
		await store.skipReceivedActions()

		// Exhaustive: rows scroll in and out of the lazy sidebar constantly, and each
		// reappearance re-running git would be a process per row per scroll.
		store.exhaustivity = .on
		await store.send(.onAppear)
	}

	@Test("a refresh re-reads git status, the stash list and the Xcode project, every time")
	func refreshFansOutEveryTime() async {
		let store = makeStore()

		await store.send(.onAppear)
		await store.finish()

		for _ in 1 ... 2 {
			await store.send(.refresh)
			await store.receive(\.gitActionsMenu.refresh)
			await store.receive(\.xcodeButton.refresh)
			await store.receive(\.didFetchStatus)
			await store.finish()
		}
	}

	// MARK: - Git menu completions

	@Test("every finished git operation refreshes the row", arguments: Completion.allCases)
	func completionRefreshesRow(completion: Completion) async {
		let store = makeStore()

		await store.send(.gitActionsMenu(completion.action))
		await store.receive(\.refresh)
		await store.finish()
	}

	@Test("menu actions that are not a finished operation do not refresh the row")
	func nonCompletionDoesNotRefresh() async {
		let store = makeStore()
		store.exhaustivity = .on

		// The stash lookup's answer is the menu action closest to a completion without being one.
		await store.send(.gitActionsMenu(.stashButton(.didFindStash(nil))))
		await store.finish()
	}

	// MARK: - Staging sheet

	@Test("closing the staging sheet refreshes the row it was opened from")
	func stagingSheetDismissRefreshes() async {
		var row = RepositoryRowReducer.State(
			path: "/repos/app",
			name: "app",
			branchName: "main",
			iosSubfolderPath: "ios"
		)
		row.isLoaded = true
		let store = makeStore(row)
		store.exhaustivity = .on

		await store.send(.openRepositoryDetail) {
			$0.repositoryDetail = RepositoryDetail.State(repositoryPath: "/repos/app", iosSubfolderPath: "ios")
		}

		store.exhaustivity = .off
		// A commit or push made in the sheet changed the row's counts.
		await store.send(.repositoryDetail(.dismiss))
		await store.receive(\.refresh)
		await store.finish()
		#expect(store.state.repositoryDetail == nil)
	}

	// MARK: - Worktree lifecycle

	@Test("a removed worktree tells the list to rescan")
	func removedWorktreeReportsDeletion() async {
		let store = makeStore(worktreeRow())

		await store.send(.deleteWorktreeButton(.didRemoveSuccessfully))
		await store.receive(\.worktreeDeleted)
		await store.finish()
	}

	@Test("a removal with warnings rescans only once its alert is dismissed")
	func removalWarningWaitsForDismissal() async {
		let store = makeStore(worktreeRow())
		store.exhaustivity = .on

		// Rescanning now would rebuild the rows and take the alert down before it is read.
		await store.send(.deleteWorktreeButton(.didRemoveSuccessfullyWithWarning("branch kept"))) {
			$0.deleteWorktreeButton.removalWarningAlert = AlertState {
				TextState("Worktree Removed")
			} actions: {
				ButtonState(role: .cancel) { TextState("OK") }
			} message: {
				TextState("Worktree was removed successfully, but:\n\nbranch kept")
			}
		}

		await store.send(.deleteWorktreeButton(.removalWarningAlert(.dismiss))) {
			$0.deleteWorktreeButton.removalWarningAlert = nil
		}
		await store.receive(\.worktreeDeleted)
	}

	@Test("a failed removal does not rescan")
	func failedRemovalDoesNotReport() async {
		let store = makeStore(worktreeRow())
		store.exhaustivity = .on

		await store.send(.deleteWorktreeButton(.didFailWithError("locked"))) {
			$0.deleteWorktreeButton.errorAlert = AlertState {
				TextState("Removal Error")
			} actions: {
				ButtonState(role: .cancel) { TextState("OK") }
			} message: {
				TextState("locked")
			}
		}
	}

	@Test("a created worktree tells the list to rescan; a failed one does not")
	func createdWorktreeReportsCreation() async {
		let store = makeStore()

		await store.send(.createWorktreeButton(.didCreateSuccessfully(copyResult: nil)))
		await store.receive(\.worktreeCreated)
		await store.finish()

		store.exhaustivity = .on
		await store.send(.createWorktreeButton(.didFailWithError("exists"))) {
			$0.createWorktreeButton.errorAlert = AlertState {
				TextState("Creation Error")
			} actions: {
				ButtonState(role: .cancel) { TextState("OK") }
			} message: {
				TextState("exists")
			}
		}
	}

	// MARK: - Commit graph

	@Test("a commit graph action that changed the repository refreshes the row")
	func graphChangeRefreshesRow() async {
		let store = makeStore()

		await store.send(.repositoryIconTapped)
		await store.send(.gitGraph(.presented(.delegate(.repositoryChanged))))
		await store.receive(\.refresh)
		await store.finish()
		#expect(store.state.gitGraph != nil)
	}

	@Test("a worktree created from the commit graph tells the list to rescan")
	func graphWorktreeReportsCreation() async {
		let store = makeStore()

		await store.send(.repositoryIconTapped)
		await store.send(.gitGraph(.presented(.delegate(.worktreeCreated))))
		await store.receive(\.worktreeCreated)
		await store.finish()
	}

		// MARK: - Helpers

	/// Each finished operation the git menu can report, success or failure alike — a failed pull
	/// or merge can still have moved the branch or left conflicts.
	enum Completion: String, CaseIterable, Sendable {
		case abortMerge, checkoutDefaultBranch, discard, fetch, mergeMaster, pull, push
		case stash, stashApply, stashClear, stashPop

		var action: GitActionsMenuReducer.Action {
			switch self {
			case .abortMerge: .abortMergeButton(.abortMergeCompleted(success: true, error: nil))
			case .checkoutDefaultBranch: .checkoutDefaultBranchButton(.checkoutCompleted(result: .success("master")))
			case .discard: .discardButton(.discardCompleted(success: true, error: nil))
			case .fetch: .fetchButton(.fetchCompleted(result: nil, error: nil))
			case .mergeMaster: .mergeMasterButton(.mergeMasterCompleted(result: .failure(.mergeFailed("conflict"))))
			case .pull: .pullButton(.pullCompleted(result: nil, error: .pullFailed("rejected")))
			case .push: .pushButton(.pushCompleted(result: nil, error: nil))
			case .stash: .stashButton(.stashCompleted(success: true, error: nil))
			case .stashApply: .stashButton(.stashApplyCompleted(success: true, error: nil))
			case .stashClear: .stashButton(.stashClearCompleted(success: true, error: nil))
			case .stashPop: .stashButton(.stashPopCompleted(success: false, error: "conflict"))
			}
		}
	}

	private func worktreeRow() -> RepositoryRowReducer.State {
		RepositoryRowReducer.State(
			path: "/repos/worktrees/app/feature",
			name: "app",
			branchName: "feature",
			isWorktree: true
		)
	}

	/// Non-exhaustive by default. The leaves a refresh reaches are stubbed: a failed status
	/// short-circuits the YouTrack/PR follow-ups, and no Xcode project is found.
	private func makeStore(
		_ row: RepositoryRowReducer.State = RepositoryRowReducer.State(path: "/repos/app", name: "app", branchName: "main")
	) -> TestStoreOf<RepositoryRowReducer> {
		let store = TestStore(initialState: row) {
			RepositoryRowReducer()
		} withDependencies: {
			$0[GitClient.self].getCurrentBranch = { _ in
				GitPorcelainStatus(parsing: "", didSucceed: false)
			}
			$0[XcodeClient.self].findXcodeProject = { _, _, _ in nil }
		}
		store.exhaustivity = .off
		return store
	}
}
