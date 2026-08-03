import ComposableArchitecture
import Settings
import Testing
@testable import RepositoryFeature

@Suite("Repository list refresh progress")
struct RepositoryListRefreshProgressTests {
	private func makeRow(path: String, isRefreshing: Bool = false) -> RepositoryRowReducer.State {
		var row = RepositoryRowReducer.State(path: path, name: "app", branchName: "master")
		row.isRefreshing = isRefreshing
		return row
	}

	private func makeGroup(
		headerIsRefreshing: Bool = false,
		refreshingWorktreeCount: Int = 0,
		idleWorktreeCount: Int = 0
	) -> RepoGroupReducer.State {
		let refreshing = (0 ..< refreshingWorktreeCount)
			.map { makeRow(path: "/repos/app-wt-refreshing-\($0)", isRefreshing: true) }
		let idle = (0 ..< idleWorktreeCount)
			.map { makeRow(path: "/repos/app-wt-idle-\($0)") }
		return RepoGroupReducer.State(
			id: "/repos/app",
			isCollapsed: false,
			header: makeRow(path: "/repos/app", isRefreshing: headerIsRefreshing),
			worktrees: IdentifiedArrayOf(uniqueElements: refreshing + idle),
			settings: RepoGroupSettings()
		)
	}

	@Test("a refreshing header row counts as in progress")
	func refreshingHeaderIsInProgress() {
		#expect(isAnyRowRefreshing(in: [makeGroup(headerIsRefreshing: true)]))
	}

	@Test("a refreshing worktree row counts as in progress")
	func refreshingWorktreeIsInProgress() {
		#expect(isAnyRowRefreshing(in: [makeGroup(refreshingWorktreeCount: 1)]))
	}

	@Test("still in progress while only some rows have finished")
	func partiallyFinishedIsStillInProgress() {
		#expect(isAnyRowRefreshing(in: [
			makeGroup(refreshingWorktreeCount: 1, idleWorktreeCount: 2)
		]))
	}

	@Test("no refreshing rows means no refresh in progress")
	func allIdleIsNotInProgress() {
		#expect(!isAnyRowRefreshing(in: [makeGroup(idleWorktreeCount: 2)]))
	}

	@Test("an empty list is not refreshing")
	func emptyListIsNotInProgress() {
		#expect(!isAnyRowRefreshing(in: []))
	}
}
