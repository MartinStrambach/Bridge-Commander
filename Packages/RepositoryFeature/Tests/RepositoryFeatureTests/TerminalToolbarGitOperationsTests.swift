import AppUI
import ComposableArchitecture
import Foundation
// Testable for the menu's alert, which only its own views read.
@testable import GitActionsMenu
import GitCore
import Testing
import ToolsIntegration
@testable import RepositoryFeature

// The terminal toolbar's git operations (its Git Actions menu, Push and Finish Merge) run on the
// opened row's own state. They used to run in `TerminalLayoutReducer.State`: hiding the panel nils
// that state, so `ifLet` cancelled the operation — SIGTERMing git with no error shown — and their
// completions refreshed whichever repository the panel showed by then, not the one they ran on.
@Suite("Terminal toolbar git operations run on the opened row")
@MainActor
struct TerminalToolbarGitOperationsTests {
	// MARK: - Push

	@Test("a push from the toolbar finishes, and refreshes its row, after the panel is hidden")
	func pushSurvivesHidingPanel() async {
		let (gate, release) = AsyncStream.makeStream(of: Void.self)
		let store = await makeStoreShowingAlpha {
			$0[GitClient.self].push = { _ in
				for await _ in gate { break }
				return GitPushHelper.PushResult(isUpToDate: false, message: "")
			}
		}

		await tapToolbarPush(store)
		#expect(toolbarIsPushing(store))

		await store.send(.terminalLayout(.hideTerminalMode))
		release.yield()

		await store.receive { isRowRefresh($0, path: "/repos/alpha") }
		#expect(store.state.repositoryGroups[id: "/repos/alpha"]?.header.gitActionsMenu.isPushing == false)
		await store.finish()
	}

	@Test("switching repositories mid-push refreshes the one that pushed, and shows no push on the other")
	func pushStaysWithItsRepository() async {
		let (gate, release) = AsyncStream.makeStream(of: Void.self)
		let pushed = LockIsolated<[String]>([])
		let store = await makeStoreShowingAlpha {
			$0[GitClient.self].push = { path in
				pushed.withValue { $0.append(path) }
				for await _ in gate { break }
				return GitPushHelper.PushResult(isUpToDate: false, message: "")
			}
		}

		await tapToolbarPush(store)
		await store.send(.terminalLayout(.selectRepo(repositoryPath: "/repos/beta")))
		#expect(!toolbarIsPushing(store))

		release.yield()
		await store.receive { isRowRefresh($0, path: "/repos/alpha") }
		#expect(pushed.value == ["/repos/alpha"])
		await store.finish()
	}

	@Test("a successful push from the toolbar refreshes its row without an alert")
	func toolbarPushSuccessIsSilent() async {
		let store = await makeStoreShowingAlpha {
			$0[GitClient.self].push = { _ in GitPushHelper.PushResult(isUpToDate: false, message: "") }
		}

		await tapToolbarPush(store)
		await store.receive { isRowRefresh($0, path: "/repos/alpha") }
		#expect(store.state.repositoryGroups[id: "/repos/alpha"]?.header.gitActionsMenu.alert == nil)
		await store.finish()
	}

	@Test("a failed push from the toolbar alerts, and refreshes its row")
	func toolbarPushFailureAlerts() async {
		let error = GitError.pushFailed("rejected: non-fast-forward")
		let store = await makeStoreShowingAlpha {
			$0[GitClient.self].push = { _ in throw error }
		}

		await tapToolbarPush(store)
		await store.receive { isRowRefresh($0, path: "/repos/alpha") }
		#expect(
			store.state.repositoryGroups[id: "/repos/alpha"]?.header.gitActionsMenu.alert
				== ScrollableAlertReducer.State(title: "Push Failed", message: error.localizedDescription, isError: true)
		)
		await store.finish()
	}

	// MARK: - Git Actions menu

	@Test("a pull from the toolbar's git menu finishes on its row after the panel is hidden")
	func menuOperationSurvivesHidingPanel() async {
		let (gate, release) = AsyncStream.makeStream(of: Void.self)
		let store = await makeStoreShowingAlpha {
			$0[GitClient.self].pull = { _ in
				for await _ in gate { break }
				return GitPullHelper.PullResult(commitCount: 0, isAlreadyUpToDate: true)
			}
		}

		await tapToolbarPull(store)
		await store.send(.terminalLayout(.hideTerminalMode))
		release.yield()

		await store.receive(\.repositoryGroups[id: "/repos/alpha"].header.gitActionsMenu.pullButton.pullCompleted)
		await store.receive { isRowRefresh($0, path: "/repos/alpha") }
		await store.finish()
	}

	@Test("switching repositories mid-pull lands the result on the repository that pulled")
	func menuOperationStaysWithItsRepository() async {
		let (gate, release) = AsyncStream.makeStream(of: Void.self)
		let store = await makeStoreShowingAlpha {
			$0[GitClient.self].pull = { _ in
				for await _ in gate { break }
				return GitPullHelper.PullResult(commitCount: 0, isAlreadyUpToDate: true)
			}
		}

		await tapToolbarPull(store)
		await store.send(.terminalLayout(.selectRepo(repositoryPath: "/repos/beta")))
		release.yield()

		await store.receive(\.repositoryGroups[id: "/repos/alpha"].header.gitActionsMenu.pullButton.pullCompleted)
		await store.receive { isRowRefresh($0, path: "/repos/alpha") }
		await store.finish()
	}

	// MARK: - Finish Merge

	@Test("Finish Merge from the banner completes, and refreshes its row, after the panel is hidden")
	func finishMergeSurvivesHidingPanel() async {
		let (gate, release) = AsyncStream.makeStream(of: Void.self)
		let store = await makeStoreShowingAlpha {
			$0[GitClient.self].finishMerge = { _ in
				for await _ in gate { break }
			}
		}

		await tapFinishMerge(store)
		#expect(bannerIsFinishingMerge(store))

		await store.send(.terminalLayout(.hideTerminalMode))
		release.yield()

		await store.receive { isRowRefresh($0, path: "/repos/alpha") }
		#expect(store.state.repositoryGroups[id: "/repos/alpha"]?.header.isFinishingMerge == false)
		await store.finish()
	}

	@Test("the Finish Merge spinner stays with the repository finishing its merge")
	func finishMergeSpinnerStaysWithItsRepository() async {
		let (gate, release) = AsyncStream.makeStream(of: Void.self)
		let store = await makeStoreShowingAlpha {
			$0[GitClient.self].finishMerge = { _ in
				for await _ in gate { break }
			}
		}

		await tapFinishMerge(store)
		await store.send(.terminalLayout(.selectRepo(repositoryPath: "/repos/beta")))
		#expect(!bannerIsFinishingMerge(store))

		release.yield()
		await store.receive { isRowRefresh($0, path: "/repos/alpha") }
		await store.finish()
	}

	@Test("a failed Finish Merge alerts")
	func finishMergeFailureAlerts() async {
		let store = await makeStoreShowingAlpha {
			$0[GitClient.self].finishMerge = { _ in
				throw GitError.mergeFailed("CONFLICT in App.swift")
			}
		}

		await tapFinishMerge(store)
		await store.finish()
		await store.skipReceivedActions()

		#expect(store.state.alert == AlertState {
			TextState("Finish Merge Failed")
		} message: {
			TextState(GitError.mergeFailed("CONFLICT in App.swift").localizedDescription)
		})
		#expect(store.state.repositoryGroups[id: "/repos/alpha"]?.header.isFinishingMerge == false)
	}

	// MARK: - No copies

	@Test("the terminal panel keeps no copy of the row's git menu or buttons")
	func terminalLayoutHoldsNoRowCopies() async throws {
		let store = await makeStoreShowingAlpha { _ in }
		let layout = try #require(store.state.terminalLayout)

		// Anything the toolbar acts on is the row's; a copy here would be cancelled by hiding
		// the panel and would go on acting on one repository after the panel moved to another.
		let labels = Mirror(reflecting: layout).children.compactMap(\.label)
		for name in ["gitActionsMenu", "Pushing", "FinishingMerge", "androidStudio", "webButton", "ticketButton"] {
			#expect(!labels.contains { $0.localizedCaseInsensitiveContains(name) }, "\(name)")
		}
	}

	// MARK: - What the toolbar sends and shows

	// `TerminalPanelView` sends these to, and reads these from, `activeRowStore`: the row of the
	// repository the panel shows. Every repository here is its group's header row.

	private func tapToolbarPush(_ store: TestStoreOf<RepositoryListReducer>) async {
		await sendToActiveRow(.gitActionsMenu(.pushButton(.quietPushTapped)), store)
	}

	private func tapToolbarPull(_ store: TestStoreOf<RepositoryListReducer>) async {
		await sendToActiveRow(.gitActionsMenu(.pullButton(.pullTapped)), store)
	}

	private func tapFinishMerge(_ store: TestStoreOf<RepositoryListReducer>) async {
		await sendToActiveRow(.finishMergeTapped, store)
	}

	private func toolbarIsPushing(_ store: TestStoreOf<RepositoryListReducer>) -> Bool {
		activeRow(store)?.gitActionsMenu.isPushing == true
	}

	private func bannerIsFinishingMerge(_ store: TestStoreOf<RepositoryListReducer>) -> Bool {
		activeRow(store)?.isFinishingMerge == true
	}

	private func activeRow(_ store: TestStoreOf<RepositoryListReducer>) -> RepositoryRowReducer.State? {
		store.state.terminalLayout?.activeRepositoryPath.flatMap { store.state.repositoryGroups[id: $0]?.header }
	}

	private func sendToActiveRow(
		_ action: RepositoryRowReducer.Action,
		_ store: TestStoreOf<RepositoryListReducer>
	) async {
		guard let path = store.state.terminalLayout?.activeRepositoryPath else {
			Issue.record("No repository open in the panel")
			return
		}
		await store.send(.repositoryGroups(.element(id: path, action: .header(action))))
	}

	// MARK: - Helpers

	private func isRowRefresh(_ action: RepositoryListReducer.Action, path: String) -> Bool {
		guard case let .repositoryGroups(.element(id: id, action: .header(.refresh))) = action else {
			return false
		}
		return id == path
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
			// short-circuits the follow-ups, and a missing origin remote the PR lookup.
			$0[GitClient.self].getCurrentBranch = { _ in
				GitPorcelainStatus(parsing: "", didSucceed: false)
			}
			$0[GitClient.self].getOriginRemote = { _ in nil }
			$0[XcodeClient.self].findXcodeProject = { _, _, _ in nil }
			$0[LastOpenedDirectoryClient.self].load = { nil }
			dependencies(&$0)
		}
		store.exhaustivity = .off
		for name in ["alpha", "beta"] {
			await store.send(.didScanGroup(rootPath: "/repos/\(name)", rows: [
				ScannedRepository(
					path: "/repos/\(name)",
					name: name,
					directory: "/repos/\(name)",
					isWorktree: false,
					branchName: "master"
				),
			]))
		}
		await store.send(.terminalLayout(.selectRepo(repositoryPath: "/repos/alpha")))
		return store
	}
}
