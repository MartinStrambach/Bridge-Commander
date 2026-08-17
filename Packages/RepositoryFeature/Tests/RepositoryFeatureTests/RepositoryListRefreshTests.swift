import ComposableArchitecture
import GitCore
import Testing
import ToolsIntegration
@testable import RepositoryFeature

// Covers the two effects in RepositoryListReducer that fan out to child rows:
// the staggered refresh sequence and the debounced re-sort after a YouTrack burst.
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

	// MARK: - Helpers

	private func makeStore(
		clock: any Clock<Duration> = ImmediateClock()
	) -> TestStoreOf<RepositoryListReducer> {
		TestStore(initialState: RepositoryListReducer.State()) {
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
