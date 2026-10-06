import ComposableArchitecture
import Foundation
import GitCore
import Settings
import TerminalFeature
import Testing
import ToolsIntegration
@testable import RepositoryFeature

// The terminal panel's tab actions as `RepositoryListReducer` applies them — the paths around the
// ones the close-tab, persistence and re-sync suites already cover: closing what is *not* on
// screen, closing the last of everything, retrying a tab, hiding the panel, and the toolbar's
// Finish Merge completion.
@Suite("Terminal tab lifecycle")
@MainActor
struct TerminalTabLifecycleTests {
	// MARK: - Closing tabs that are not on screen

	@Test("closing a background tab leaves the tab on screen, and its memory, alone")
	func killBackgroundTabKeepsActiveTab() async {
		let alphaOne = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		let alphaTwo = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 2)
		let store = TestStore(initialState: state(sessions: [alphaOne, alphaTwo], active: alphaTwo)) {
			RepositoryListReducer()
		}

		await store.send(.terminalLayout(.killTab(sessionId: alphaOne.id))) {
			$0.terminalSessions.remove(id: alphaOne.id)
		}
	}

	@Test("closing a background repository's terminals keeps the panel where it is")
	func killBackgroundRepoKeepsActiveRepo() async {
		let alpha = TerminalSession(repositoryPath: "/repos/alpha")
		let betaOne = TerminalSession(repositoryPath: "/repos/beta", tabIndex: 1)
		let betaTwo = TerminalSession(repositoryPath: "/repos/beta", tabIndex: 2)
		var initial = state(sessions: [alpha, betaOne, betaTwo], active: alpha)
		initial.terminalLayout?.lastActiveSessionByRepo["/repos/beta"] = betaTwo.id
		let store = TestStore(initialState: initial) {
			RepositoryListReducer()
		}

		await store.send(.terminalLayout(.killRepo(repositoryPath: "/repos/beta"))) {
			$0.terminalSessions.remove(id: betaOne.id)
			$0.terminalSessions.remove(id: betaTwo.id)
			$0.terminalLayout?.lastActiveSessionByRepo["/repos/beta"] = nil
		}
	}

	// MARK: - Closing the last of everything

	@Test("closing the only tab left anywhere closes the panel")
	func killLastTabClosesPanel() async {
		let alpha = TerminalSession(repositoryPath: "/repos/alpha")
		let store = TestStore(initialState: state(sessions: [alpha], active: alpha)) {
			RepositoryListReducer()
		}

		await store.send(.terminalLayout(.killTab(sessionId: alpha.id))) {
			$0.terminalSessions = []
			$0.terminalLayout = nil
		}
	}

	@Test("closing the only repository with terminals closes the panel")
	func killLastRepoClosesPanel() async {
		let alphaOne = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		let alphaTwo = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 2)
		let store = TestStore(initialState: state(sessions: [alphaOne, alphaTwo], active: alphaOne)) {
			RepositoryListReducer()
		}

		await store.send(.terminalLayout(.killRepo(repositoryPath: "/repos/alpha"))) {
			$0.terminalSessions = []
			$0.terminalLayout = nil
		}
	}

	@Test("hiding the panel keeps every terminal running")
	func hidePanelKeepsSessions() async {
		let alpha = TerminalSession(repositoryPath: "/repos/alpha")
		let beta = TerminalSession(repositoryPath: "/repos/beta")
		let store = TestStore(initialState: state(sessions: [alpha, beta], active: alpha)) {
			RepositoryListReducer()
		}

		// Exhaustive: the sessions are what `killSessions(notIn:)` diffs against, so dropping
		// any of them here would hang up its shell.
		await store.send(.terminalLayout(.hideTerminalMode)) {
			$0.hiddenTerminalTabMemory = $0.terminalLayout?.tabMemory
			$0.terminalLayout = nil
		}
	}

	// MARK: - Stale and empty requests

	@Test("selecting a tab that has already closed changes nothing")
	func selectClosedTabIsIgnored() async {
		let alpha = TerminalSession(repositoryPath: "/repos/alpha")
		let store = TestStore(initialState: state(sessions: [alpha], active: alpha)) {
			RepositoryListReducer()
		}

		await store.send(.terminalLayout(.selectTab(sessionId: UUID())))
		await store.send(.terminalLayout(.retryTab(sessionId: UUID())))
		await store.send(.terminalLayout(.killTab(sessionId: UUID())))
	}

	@Test("a new tab with no repository on screen opens nothing")
	func newTabWithoutActiveRepoIsIgnored() async {
		var initial = RepositoryListReducer.State()
		initial.terminalLayout = TerminalLayoutReducer.State()
		let store = TestStore(initialState: initial) {
			RepositoryListReducer()
		}

		await store.send(.terminalLayout(.newTabRequested))
	}

	@Test("a new tab is numbered after the highest open one, so a closed number is not reused")
	func newTabNumberFollowsHighestOpenTab() async {
		let alphaOne = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		let alphaThree = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 3)
		let beta = TerminalSession(repositoryPath: "/repos/beta", tabIndex: 7)
		let store = TestStore(initialState: state(sessions: [alphaOne, alphaThree, beta], active: alphaOne)) {
			RepositoryListReducer()
		}
		store.exhaustivity = .off

		await store.send(.terminalLayout(.newTabRequested))

		let newTab = store.state.terminalSessions.last
		#expect(newTab?.repositoryPath == "/repos/alpha")
		// 4, not 2 (the gap) and not 8 (another repository's numbering).
		#expect(newTab?.tabIndex == 4)
		#expect(store.state.terminalLayout?.activeSessionId == newTab?.id)
	}

	// MARK: - Retrying a tab

	@Test("a retried tab keeps its number and its place in the bar, and is the one on screen")
	func retryKeepsNumberAndPlace() async {
		let alphaOne = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		var alphaTwo = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 2)
		alphaTwo.status = .failed("exec failed")
		let alphaThree = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 3)
		let store = TestStore(
			initialState: state(sessions: [alphaOne, alphaTwo, alphaThree], active: alphaOne)
		) {
			RepositoryListReducer()
		}
		store.exhaustivity = .off

		await store.send(.terminalLayout(.retryTab(sessionId: alphaTwo.id)))

		let sessions = store.state.terminalSessions
		#expect(sessions[id: alphaTwo.id] == nil)
		// The bar lays tabs out in array order, so where the replacement lands is where it shows.
		#expect(sessions.map(\.tabIndex) == [1, 2, 3])
		let retried = sessions[1]
		#expect(retried.status == .launching)
		#expect(store.state.terminalLayout?.activeSessionId == retried.id)
		#expect(store.state.terminalLayout?.lastActiveSessionByRepo["/repos/alpha"] == retried.id)
	}

	// MARK: - Toolbar Finish Merge

	@Test("a finished merge from the toolbar refreshes the opened repository's row")
	func finishMergeRefreshesRow() async {
		let store = await makeStoreShowingAlpha()

		await store.send(.terminalLayout(.finishMergeCompleted(repositoryPath: "/repos/alpha", error: nil)))
		await store.receive { isHeaderRefresh($0, groupId: "/repos/alpha") }
		await store.finish()
		#expect(store.state.alert == nil)
	}

	@Test("a failed merge from the toolbar alerts instead of refreshing")
	func finishMergeFailureAlerts() async {
		let store = await makeStoreShowingAlpha()
		store.exhaustivity = .on

		await store.send(.terminalLayout(.finishMergeCompleted(
			repositoryPath: "/repos/alpha",
			error: .mergeFailed("CONFLICT in App.swift")
		))) {
			$0.alert = AlertState {
				TextState("Finish Merge Failed")
			} message: {
				TextState(GitError.mergeFailed("CONFLICT in App.swift").localizedDescription)
			}
		}
	}

	// MARK: - Toolbar buttons

	@Test("the toolbar shows Android Studio only for a repository that supports Android")
	func androidStudioButtonFollowsSupport() async {
		@Shared(.groupSettings) var groupSettings: [String: RepoGroupSettings] = [:]
		$groupSettings.withLock {
			$0 = ["/repos/alpha": RepoGroupSettings(supportsAndroid: true)]
		}
		let store = await makeStoreShowingAlpha()

		#expect(store.state.terminalLayout?.androidStudioButton != nil)
		#expect(
			store.state.terminalLayout?.androidStudioButton
				== store.state.repositoryGroups[id: "/repos/alpha"]?.header.androidStudioButton
		)

		await store.send(.terminalLayout(.selectRepo(repositoryPath: "/repos/beta")))
		#expect(store.state.terminalLayout?.androidStudioButton == nil)
	}

	@Test("a repository supporting iOS and Android opens its first terminal in the mobile subfolder")
	func firstTabStartsInMobileSubfolder() async {
		@Shared(.groupSettings) var groupSettings: [String: RepoGroupSettings] = [:]
		$groupSettings.withLock {
			$0 = [
				"/repos/alpha": RepoGroupSettings(supportsIOS: true, supportsAndroid: true, mobileSubfolderPath: "/mobile/"),
				"/repos/beta": RepoGroupSettings(supportsIOS: true, mobileSubfolderPath: "mobile"),
			]
		}
		let store = await makeStoreShowingAlpha()

		let directories = Dictionary(
			uniqueKeysWithValues: store.state.terminalSessions.map { ($0.repositoryPath, $0.startingDirectory) }
		)
		#expect(directories["/repos/alpha"] == "/repos/alpha/mobile")
		// The subfolder only applies when both platforms live side by side under it.
		#expect(directories["/repos/beta"] == "/repos/beta")
	}

	// MARK: - Helpers

	/// Sessions only, no rows: enough for tab bookkeeping, which never needs a row.
	private func state(sessions: [TerminalSession], active: TerminalSession) -> RepositoryListReducer.State {
		var state = RepositoryListReducer.State()
		state.terminalSessions = IdentifiedArray(uniqueElements: sessions)
		var layout = TerminalLayoutReducer.State()
		layout.activate(active)
		state.terminalLayout = layout
		return state
	}

	/// Two scanned repositories with a terminal each; alpha is the one on screen. Non-exhaustive.
	private func makeStoreShowingAlpha() async -> TestStoreOf<RepositoryListReducer> {
		var initialState = RepositoryListReducer.State()
		initialState.terminalLayout = TerminalLayoutReducer.State()
		let store = TestStore(initialState: initialState) {
			RepositoryListReducer()
		} withDependencies: {
			$0.continuousClock = ImmediateClock()
			$0[GitClient.self].getCurrentBranch = { _ in
				GitPorcelainStatus(parsing: "", didSucceed: false)
			}
			$0[GitClient.self].getOriginRemote = { _ in nil }
			$0[XcodeClient.self].findXcodeProject = { _, _, _ in nil }
			$0[LastOpenedDirectoryClient.self].load = { nil }
		}
		store.exhaustivity = .off
		await store.send(.didScanGroup(rootPath: "/repos/alpha", rows: [mainRepo("/repos/alpha")]))
		await store.send(.didScanGroup(rootPath: "/repos/beta", rows: [mainRepo("/repos/beta")]))
		await store.send(.terminalLayout(.selectRepo(repositoryPath: "/repos/beta")))
		await store.send(.terminalLayout(.selectRepo(repositoryPath: "/repos/alpha")))
		return store
	}

	private func mainRepo(_ path: String) -> ScannedRepository {
		ScannedRepository(
			path: path,
			name: (path as NSString).lastPathComponent,
			directory: path,
			isWorktree: false,
			branchName: "master"
		)
	}

	private func isHeaderRefresh(_ action: RepositoryListReducer.Action, groupId: String) -> Bool {
		guard case let .repositoryGroups(.element(id: id, action: .header(.refresh))) = action else {
			return false
		}
		return id == groupId
	}
}
