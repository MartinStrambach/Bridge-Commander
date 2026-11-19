import ComposableArchitecture
import Foundation
import GitCore
import Settings
import TerminalFeature
import Testing
import ToolsIntegration
@testable import RepositoryFeature

// A worktree's terminals go with its row, whichever way the row went: the row's own
// `worktreeDeleted` is not the only way out. A worktree removed in a terminal never sends it, and
// one deleted from the app can lose its row to the live watcher's rescan first, while the delete
// is still clearing the branch and DerivedData — the row's report then has no row to come from.
@Suite("Terminals of a worktree a scan no longer finds")
@MainActor
struct RemovedWorktreeTerminalTests {
	@Test("a scan that no longer lists the worktree closes its tabs and moves the panel on")
	func scanClosesTheRemovedWorktreesTabs() async {
		let alpha = TerminalSession(repositoryPath: "/repos/alpha")
		let goneOne = TerminalSession(repositoryPath: "/repos/alpha-gone", tabIndex: 1)
		let goneTwo = TerminalSession(repositoryPath: "/repos/alpha-gone", tabIndex: 2)
		let store = makeStore(sessions: [alpha, goneOne, goneTwo], active: goneTwo)
		await scanAlpha(store, worktrees: ["/repos/alpha-gone", "/repos/alpha-kept"])

		await scanAlpha(store, worktrees: ["/repos/alpha-kept"])

		#expect(store.state.terminalSessions.map(\.id) == [alpha.id])
		#expect(store.state.terminalLayout?.activeSessionId == alpha.id)
		#expect(store.state.terminalLayout?.activeRepositoryPath == "/repos/alpha")
		#expect(store.state.terminalLayout?.lastActiveSessionByRepo["/repos/alpha-gone"] == nil)
	}

	@Test("the panel closes when the removed worktree's tabs were the only ones")
	func scanClosesThePanelWithTheLastTabs() async {
		let gone = TerminalSession(repositoryPath: "/repos/alpha-gone")
		let store = makeStore(sessions: [gone], active: gone)
		await scanAlpha(store, worktrees: ["/repos/alpha-gone"])

		await scanAlpha(store, worktrees: [])

		#expect(store.state.terminalSessions.isEmpty)
		#expect(store.state.terminalLayout == nil)
	}

	@Test("tabs close with the panel hidden too")
	func scanClosesTabsBehindAHiddenPanel() async {
		let alpha = TerminalSession(repositoryPath: "/repos/alpha")
		let gone = TerminalSession(repositoryPath: "/repos/alpha-gone")
		let store = makeStore(sessions: [alpha, gone], active: gone)
		await scanAlpha(store, worktrees: ["/repos/alpha-gone"])
		await store.send(.terminalLayout(.hideTerminalMode))

		await scanAlpha(store, worktrees: [])

		#expect(store.state.terminalSessions.map(\.id) == [alpha.id])
		#expect(store.state.terminalLayout == nil)
	}

	@Test("a scan that failed, and so lists nothing, closes nothing")
	func failedScanKeepsEveryTab() async {
		let alpha = TerminalSession(repositoryPath: "/repos/alpha")
		let worktree = TerminalSession(repositoryPath: "/repos/alpha-wt")
		let store = makeStore(sessions: [alpha, worktree], active: worktree)
		await scanAlpha(store, worktrees: ["/repos/alpha-wt"])

		await store.send(.didScanGroup(rootPath: "/repos/alpha", rows: []))

		#expect(store.state.terminalSessions.map(\.id) == [alpha.id, worktree.id])
		#expect(store.state.terminalLayout?.activeSessionId == worktree.id)
	}

	@Test("a tab whose repository has no row yet, as after a relaunch, survives the scan")
	func scanKeepsTabsOfRowsItNeverHad() async {
		let restored = TerminalSession(repositoryPath: "/repos/alpha-restored")
		let store = makeStore(sessions: [restored], active: restored)
		await scanAlpha(store, worktrees: [])

		await scanAlpha(store, worktrees: ["/repos/alpha-other"])

		#expect(store.state.terminalSessions.map(\.id) == [restored.id])
	}

	// MARK: - Scans that overlap

	// Scans of one group overlap, and an older one can answer last. Its listing predates a
	// worktree made meanwhile, whose tabs — a Claude just started in it — it would hang up.
	@Test("the answer of a scan a newer one has overtaken closes nothing")
	func overtakenScanClosesNothing() async throws {
		let fresh = TerminalSession(repositoryPath: "/repos/alpha-fresh")
		let store = makeStore(sessions: [fresh], active: fresh)
		await scanAlpha(store, worktrees: [])
		// Two scans of alpha on their way: one from before the worktree was made, one after.
		await store.send(.repositoriesChangedOnDisk([worktreeListChanged]))
		let older = try #require(store.state.latestScanRequests["/repos/alpha"])
		await store.send(.repositoriesChangedOnDisk([worktreeListChanged]))
		let newer = try #require(store.state.latestScanRequests["/repos/alpha"])
		#expect(newer > older)

		await scanAlpha(store, worktrees: ["/repos/alpha-fresh"], request: newer)
		await scanAlpha(store, worktrees: [], request: older)

		#expect(alphaWorktrees(store) == ["/repos/alpha-fresh"])
		#expect(store.state.terminalSessions.map(\.id) == [fresh.id])
	}

	@Test("the latest scan's answer still closes the tabs of a worktree it no longer lists")
	func latestScanStillCloses() async throws {
		let gone = TerminalSession(repositoryPath: "/repos/alpha-gone")
		let store = makeStore(sessions: [gone], active: gone)
		await scanAlpha(store, worktrees: ["/repos/alpha-gone"])
		await store.send(.repositoriesChangedOnDisk([worktreeListChanged]))
		let latest = try #require(store.state.latestScanRequests["/repos/alpha"])

		await scanAlpha(store, worktrees: [], request: latest)

		#expect(store.state.terminalSessions.isEmpty)
	}

	// MARK: - A worktree the app is deleting

	@Test("a finished delete closes the worktree's tabs")
	func finishedDeleteClosesTabs() async {
		let alpha = TerminalSession(repositoryPath: "/repos/alpha")
		let gone = TerminalSession(repositoryPath: "/repos/alpha-gone")
		let store = makeStore(sessions: [alpha, gone], active: gone)
		await scanAlpha(store, worktrees: ["/repos/alpha-gone"])

		await store.send(goneRow(.deleteWorktreeButton(.didRemoveSuccessfully)))
		await store.receive(\.repositoryGroups[id: "/repos/alpha"].worktrees[id: "/repos/alpha-gone"].worktreeDeleted)

		#expect(store.state.terminalSessions.map(\.id) == [alpha.id])
	}

	@Test("a removal with a warning closes the tabs at once, and keeps the row until the alert is read")
	func warningClosesTabsAndKeepsTheRow() async {
		let alpha = TerminalSession(repositoryPath: "/repos/alpha")
		let gone = TerminalSession(repositoryPath: "/repos/alpha-gone")
		let store = makeStore(sessions: [alpha, gone], active: gone)
		await scanAlpha(store, worktrees: ["/repos/alpha-gone"])

		await store.send(goneRow(.deleteWorktreeButton(.didRemoveSuccessfullyWithWarning("files left"))))
		#expect(store.state.terminalSessions.map(\.id) == [alpha.id])
		#expect(store.state.terminalLayout?.activeSessionId == alpha.id)

		// The alert hangs off the row: a scan that took the row would take the alert down unread.
		await scanAlpha(store, worktrees: [])
		#expect(alphaWorktrees(store) == ["/repos/alpha-gone"])

		await store.send(goneRow(.deleteWorktreeButton(.removalWarningAlert(.dismiss))))
		await scanAlpha(store, worktrees: [])
		#expect(alphaWorktrees(store).isEmpty)
	}

	@Test("a removal git refused keeps the worktree's tabs")
	func failedRemovalKeepsTabs() async {
		let gone = TerminalSession(repositoryPath: "/repos/alpha-gone")
		let store = makeStore(sessions: [gone], active: gone)
		await scanAlpha(store, worktrees: ["/repos/alpha-gone"])

		await store.send(goneRow(.deleteWorktreeButton(.didFailWithError("contains modified or untracked files"))))
		await scanAlpha(store, worktrees: ["/repos/alpha-gone"])

		#expect(store.state.terminalSessions.map(\.id) == [gone.id])
		#expect(store.state.terminalLayout?.activeSessionId == gone.id)
	}

	// The scan keeps a row for as long as this says; the warning test above goes through the
	// same check with the alert up.
	@Test("a row is held while its delete runs or its warning is up, and not for an error")
	func rowIsHeldUntilTheDeleteIsDone() {
		var button = DeleteWorktreeButtonReducer.State(name: "gone", path: "/repos/alpha-gone", defaultBranch: "")
		#expect(!button.holdsRowAfterRemoval)

		button.isRemoving = true
		#expect(button.holdsRowAfterRemoval)

		button.isRemoving = false
		button.removalWarningAlert = AlertState { TextState("Worktree Removed") }
		#expect(button.holdsRowAfterRemoval)

		button.removalWarningAlert = nil
		button.errorAlert = AlertState { TextState("Removal Error") }
		#expect(!button.holdsRowAfterRemoval)
	}

	// MARK: - Helpers

	private func goneRow(_ action: RepositoryRowReducer.Action) -> RepositoryListReducer.Action {
		.repositoryGroups(.element(
			id: "/repos/alpha",
			action: .worktrees(.element(id: "/repos/alpha-gone", action: action))
		))
	}

	private func alphaWorktrees(_ store: TestStoreOf<RepositoryListReducer>) -> [String] {
		store.state.repositoryGroups[id: "/repos/alpha"]?.worktrees.map(\.path) ?? []
	}

	private func makeStore(
		sessions: [TerminalSession],
		active: TerminalSession
	) -> TestStoreOf<RepositoryListReducer> {
		var initialState = RepositoryListReducer.State()
		initialState.terminalSessions = IdentifiedArray(uniqueElements: sessions)
		var layout = TerminalLayoutReducer.State()
		layout.activate(active)
		initialState.terminalLayout = layout
		let store = TestStore(initialState: initialState) {
			RepositoryListReducer()
		} withDependencies: {
			$0[GitClient.self].getCurrentBranch = { _ in
				GitPorcelainStatus(parsing: "", didSucceed: false)
			}
			$0[GitClient.self].getOriginRemote = { _ in nil }
			$0[XcodeClient.self].findXcodeProject = { _, _, _ in nil }
			$0[XcodeClient.self].projectGenerator = { _, _ in nil }
			$0[LastOpenedDirectoryClient.self].load = { nil }
		}
		store.exhaustivity = .off
		return store
	}

	private func scanAlpha(
		_ store: TestStoreOf<RepositoryListReducer>,
		worktrees: [String],
		request: Int? = nil
	) async {
		await store.send(.didScanGroup(
			rootPath: "/repos/alpha",
			rows: [scanned("/repos/alpha", isWorktree: false)] + worktrees.map { scanned($0, isWorktree: true) },
			request: request
		))
	}

	/// What the watcher reports when a worktree was added or removed; it starts a rescan of alpha.
	/// The rescan itself finds no repository at that path and so applies nothing.
	private var worktreeListChanged: GitRepositoryChange {
		GitRepositoryChange(repositoryPath: "/repos/alpha", kinds: .worktreeList)
	}

	private func scanned(_ path: String, isWorktree: Bool) -> ScannedRepository {
		ScannedRepository(
			path: path,
			name: (path as NSString).lastPathComponent,
			directory: path,
			isWorktree: isWorktree,
			branchName: isWorktree ? "fix_MOB-1" : "master"
		)
	}
}
