import ComposableArchitecture
import Foundation
import GitCore
import Testing
import ToolsIntegration
@testable import RepositoryFeature

// Covers the effects in RepositoryListReducer that route refreshes to child rows:
// the staggered full-refresh sequence, the debounced re-sort after a YouTrack burst,
// and the terminal-mode ⌘R that refreshes only the opened repo.
@Suite("Repository list refresh fan-out")
@MainActor
struct RepositoryListRefreshTests {
	// MARK: - Refresh sequence

	@Test("refresh sends startScan, then each group's header before its worktrees")
	func refreshSendsHeaderBeforeWorktreesPerGroup() async {
		let store = makeStore()
		store.exhaustivity = .off

		await store.send(.didScanGroup(rootPath: "/repos/alpha", rows: [
			mainRepo("/repos/alpha", name: "alpha"),
			worktree("/repos/alpha-one", name: "alpha-one", branch: "feature-one"),
			worktree("/repos/alpha-two", name: "alpha-two", branch: "feature-two"),
		]))
		await store.send(.didScanGroup(rootPath: "/repos/beta", rows: [
			mainRepo("/repos/beta", name: "beta"),
			worktree("/repos/beta-one", name: "beta-one", branch: "feature-three"),
		]))

		// Groups are kept sorted by header name, but the worktree order within a group is
		// whatever the active sort mode produced — read it back instead of assuming it.
		let groups = store.state.repositoryGroups.map { group in
			(groupId: group.id, worktreeIds: group.worktrees.map(\.id))
		}
		#expect(groups.map { $0.groupId } == ["/repos/alpha", "/repos/beta"])
		#expect(groups.map { $0.worktreeIds.count } == [2, 1])

		await store.send(.refreshRepositories)

		// The scan is kicked off first, then every row is refreshed one at a time.
		// `receive` consumes the action queue in order, so a header arriving after one of
		// its own worktrees (or a group interleaving with the next) fails the assertions.
		await store.receive(\.startScan)
		for group in groups {
			await store.receive { isHeaderRefresh($0, groupId: group.groupId) }
			for worktreeId in group.worktreeIds {
				await store.receive { isWorktreeRefresh($0, groupId: group.groupId, worktreeId: worktreeId) }
			}
		}

		await store.finish()
	}

	@Test("refresh does nothing when no repositories are tracked")
	func refreshWithoutGroupsIsANoOp() async {
		let store = makeStore()

		// Exhaustive: an unasserted `startScan` — or any row refresh — fails here.
		await store.send(.refreshRepositories)
		await store.finish()
	}

	// MARK: - Debounced sort

	@Test("a YouTrack fetch re-sorts once the debounce window elapses")
	func youTrackFetchSortsAfterDebounceWindow() async {
		let clock = TestClock()
		let store = makeStore(clock: clock)

		store.exhaustivity = .off
		await store.send(.didScanGroup(rootPath: "/repos/alpha", rows: [
			mainRepo("/repos/alpha", name: "alpha"),
			worktree("/repos/alpha-one", name: "alpha-one", branch: "feature-one"),
		]))
		store.exhaustivity = .on

		await store.send(.repositoryGroups(.element(
			id: "/repos/alpha",
			action: .header(.didFetchYouTrack(nil))
		)))

		await clock.advance(by: .milliseconds(300))
		await store.receive(\.performDebouncedSort)
		await store.finish()
	}

	@Test("a burst of YouTrack fetches collapses into a single re-sort")
	func youTrackBurstCollapsesIntoOneSort() async {
		let clock = TestClock()
		let store = makeStore(clock: clock)

		store.exhaustivity = .off
		await store.send(.didScanGroup(rootPath: "/repos/alpha", rows: [
			mainRepo("/repos/alpha", name: "alpha"),
			worktree("/repos/alpha-one", name: "alpha-one", branch: "feature-one"),
		]))
		store.exhaustivity = .on

		// Two fetches land 200ms apart, inside the 300ms window: the first pending sort is
		// cancelled in flight, so the burst produces one sort rather than one per fetch.
		await store.send(.repositoryGroups(.element(
			id: "/repos/alpha",
			action: .header(.didFetchYouTrack(nil))
		)))
		await clock.advance(by: .milliseconds(200))
		await store.send(.repositoryGroups(.element(
			id: "/repos/alpha",
			action: .worktrees(.element(id: "/repos/alpha-one", action: .didFetchYouTrack(nil)))
		)))
		await clock.advance(by: .milliseconds(300))

		await store.receive(\.performDebouncedSort)
		// Exhaustive: a second `performDebouncedSort` from the cancelled effect fails here.
		await store.finish()
	}

	@Test("no re-sort is scheduled while sorting by ticket instead of state")
	func youTrackFetchDoesNotSortOutsideStateMode() async {
		let clock = TestClock()
		let store = makeStore(clock: clock)

		store.exhaustivity = .off
		await store.send(.didScanGroup(rootPath: "/repos/alpha", rows: [
			mainRepo("/repos/alpha", name: "alpha"),
			worktree("/repos/alpha-one", name: "alpha-one", branch: "feature-one"),
		]))
		await store.send(.view(.sortModeButtonTapped))
		#expect(store.state.sortMode == .ticket)
		store.exhaustivity = .on

		await store.send(.repositoryGroups(.element(
			id: "/repos/alpha",
			action: .header(.didFetchYouTrack(nil))
		)))
		await clock.advance(by: .seconds(1))

		// Exhaustive: any `performDebouncedSort` reaching the queue fails here.
		await store.finish()
	}

	// MARK: - Terminal-mode single-repo refresh (⌘R)

	@Test("terminal ⌘R refreshes only the opened main repo, not the whole list")
	func terminalRefreshTargetsActiveHeaderRow() async {
		let store = makeStore(terminalActiveRepositoryPath: "/repos/alpha")

		store.exhaustivity = .off
		await store.send(.didScanGroup(rootPath: "/repos/alpha", rows: [
			mainRepo("/repos/alpha", name: "alpha"),
			worktree("/repos/alpha-one", name: "alpha-one", branch: "feature-one"),
		]))
		await store.send(.didScanGroup(rootPath: "/repos/beta", rows: [
			mainRepo("/repos/beta", name: "beta"),
		]))
		store.exhaustivity = .on

		await store.send(.terminalLayout(.refreshActiveRepoRequested))

		// Exhaustive: the alpha header refresh must be the first and only action the
		// request produces — a `startScan` or any other row's refresh fails here.
		await store.receive { isHeaderRefresh($0, groupId: "/repos/alpha") }

		// The received refresh runs the row reducer, whose own fan-out (git status,
		// actions menu, Xcode lookup) is out of scope — same as the full-refresh test.
		store.exhaustivity = .off
		await store.finish()
	}

	@Test("terminal ⌘R on a worktree refreshes that worktree, not its group header")
	func terminalRefreshTargetsActiveWorktreeRow() async {
		let store = makeStore(terminalActiveRepositoryPath: "/repos/alpha-one")

		store.exhaustivity = .off
		await store.send(.didScanGroup(rootPath: "/repos/alpha", rows: [
			mainRepo("/repos/alpha", name: "alpha"),
			worktree("/repos/alpha-one", name: "alpha-one", branch: "feature-one"),
			worktree("/repos/alpha-two", name: "alpha-two", branch: "feature-two"),
		]))
		store.exhaustivity = .on

		await store.send(.terminalLayout(.refreshActiveRepoRequested))

		// Exhaustive: a header refresh arriving first (or instead) fails here.
		await store.receive {
			isWorktreeRefresh($0, groupId: "/repos/alpha", worktreeId: "/repos/alpha-one")
		}

		store.exhaustivity = .off
		await store.finish()
	}

	@Test("terminal ⌘R re-detects the Xcode project shown in the terminal toolbar")
	func terminalRefreshRedetectsToolbarXcodeProject() async {
		// The toolbar's Xcode button is a copy of the row's state taken when the terminal
		// opened. A project generated afterwards (e.g. via tuist in the embedded shell)
		// only appears if ⌘R re-runs the on-disk lookup on the copy, not just on the row.
		let store = makeStore(
			terminalActiveRepositoryPath: "/repos/alpha",
			terminalXcodeButton: XcodeProjectButtonReducer.State(
				repositoryPath: "/repos/alpha",
				iosSubfolderPath: ""
			)
		)
		store.dependencies[XcodeClient.self].findXcodeProject = { _, _, _ in
			"/repos/alpha/App.xcodeproj"
		}

		store.exhaustivity = .off
		await store.send(.didScanGroup(rootPath: "/repos/alpha", rows: [
			mainRepo("/repos/alpha", name: "alpha"),
		]))

		await store.send(.terminalLayout(.refreshActiveRepoRequested))

		await store.receive(\.terminalLayout.xcodeButton.refresh)
		await store.receive(\.terminalLayout.xcodeButton.foundProjectPath)
		#expect(store.state.terminalLayout?.xcodeButton?.projectPath == "/repos/alpha/App.xcodeproj")

		await store.finish()
	}

	@Test("terminal ⌘R does nothing when the opened session has no repo row")
	func terminalRefreshIgnoresPathsWithoutARow() async {
		// The home-directory session is the one path selectable in the sidebar that
		// has no repository row behind it.
		let store = makeStore(terminalActiveRepositoryPath: NSHomeDirectory())

		store.exhaustivity = .off
		await store.send(.didScanGroup(rootPath: "/repos/alpha", rows: [
			mainRepo("/repos/alpha", name: "alpha"),
		]))
		store.exhaustivity = .on

		// Exhaustive: any row refresh — or a fall-through to the full refresh — fails here.
		await store.send(.terminalLayout(.refreshActiveRepoRequested))
		await store.finish()
	}

	@Test("terminal ⌘R is a no-op while no repository is selected in the sidebar")
	func terminalRefreshWithoutActiveRepoIsANoOp() async {
		let store = makeStore(terminalActiveRepositoryPath: nil, terminalLayoutOpen: true)

		store.exhaustivity = .off
		await store.send(.didScanGroup(rootPath: "/repos/alpha", rows: [
			mainRepo("/repos/alpha", name: "alpha"),
		]))
		store.exhaustivity = .on

		await store.send(.terminalLayout(.refreshActiveRepoRequested))
		await store.finish()
	}

	// MARK: - Terminal-mode refresh after an in-panel operation

	@Test("a successful push from the terminal toolbar refreshes the opened repo's row")
	func toolbarPushRefreshesActiveRow() async {
		let store = makeStore(terminalActiveRepositoryPath: "/repos/alpha")

		store.exhaustivity = .off
		await store.send(.didScanGroup(rootPath: "/repos/alpha", rows: [
			mainRepo("/repos/alpha", name: "alpha"),
		]))
		store.exhaustivity = .on

		await store.send(.terminalLayout(.pushCompleted(
			result: GitPushHelper.PushResult(isUpToDate: false, message: "pushed 2 commits"),
			error: nil
		)))

		// The toolbar's own Push button has no other route back to the row, so without this
		// refresh the unpushed count it renders keeps the pre-push value. Exhaustive: any
		// other action — or none at all — fails here.
		await store.receive { isHeaderRefresh($0, groupId: "/repos/alpha") }

		store.exhaustivity = .off
		await store.finish()
	}

	@Test("a failed push from the terminal toolbar alerts instead of refreshing")
	func toolbarPushFailureAlertsWithoutRefreshing() async {
		let store = makeStore(terminalActiveRepositoryPath: "/repos/alpha")

		store.exhaustivity = .off
		await store.send(.didScanGroup(rootPath: "/repos/alpha", rows: [
			mainRepo("/repos/alpha", name: "alpha"),
		]))
		store.exhaustivity = .on

		let error = GitError.pushFailed("rejected: non-fast-forward")
		// A rejected push leaves the local commits — and the count rendering them — exactly
		// as they were, so it reports the failure rather than re-running the status fetch.
		// Exhaustive: a row refresh reaching the queue fails here.
		await store.send(.terminalLayout(.pushCompleted(result: nil, error: error))) {
			$0.alert = AlertState {
				TextState("Push Failed")
			} message: {
				TextState(error.localizedDescription)
			}
		}
		await store.finish()
	}

	@Test("closing the staging sheet in terminal mode refreshes the opened repo's row")
	func stagingSheetDismissalRefreshesActiveRow() async {
		let store = makeStore(terminalActiveRepositoryPath: "/repos/alpha")

		store.exhaustivity = .off
		await store.send(.didScanGroup(rootPath: "/repos/alpha", rows: [
			mainRepo("/repos/alpha", name: "alpha"),
		]))
		await store.send(.terminalLayout(.stagingButtonTapped(
			repositoryPath: "/repos/alpha",
			iosSubfolderPath: ""
		)))
		store.exhaustivity = .on

		// Same parity the row gets in list mode (RepositoryRowReducer.repositoryDetail(.dismiss)):
		// a commit made in the sheet changes the row's counts, so re-run its status fetch.
		await store.send(.terminalLayout(.stagingDetail(.dismiss))) {
			$0.terminalLayout?.stagingDetail = nil
		}
		await store.receive { isHeaderRefresh($0, groupId: "/repos/alpha") }

		store.exhaustivity = .off
		await store.finish()
	}

	// MARK: - Helpers

	private func makeStore(
		clock: any Clock<Duration> = ImmediateClock(),
		terminalActiveRepositoryPath: String? = nil,
		terminalLayoutOpen: Bool = false,
		terminalXcodeButton: XcodeProjectButtonReducer.State? = nil
	) -> TestStoreOf<RepositoryListReducer> {
		var initialState = RepositoryListReducer.State()
		if terminalActiveRepositoryPath != nil || terminalLayoutOpen {
			initialState.terminalLayout = TerminalLayoutReducer.State(
				activeRepositoryPath: terminalActiveRepositoryPath,
				xcodeButton: terminalXcodeButton
			)
		}
		return TestStore(initialState: initialState) {
			RepositoryListReducer()
		} withDependencies: {
			$0.continuousClock = clock
			// A row refresh fans out to git and Xcode lookups of its own. Only the parent's
			// ordering is under test, so stub the leaves: a failed status short-circuits the
			// row's follow-up YouTrack and pull request fetches.
			$0[GitClient.self].getCurrentBranch = { _ in
				GitPorcelainStatus(parsing: "", didSucceed: false)
			}
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

	private func isWorktreeRefresh(
		_ action: RepositoryListReducer.Action,
		groupId: String,
		worktreeId: String
	) -> Bool {
		guard
			case let .repositoryGroups(.element(
				id: id,
				action: .worktrees(.element(id: rowId, action: .refresh))
			)) = action
		else {
			return false
		}
		return id == groupId && rowId == worktreeId
	}
}
