import ComposableArchitecture
import Foundation
import GitCore
import Testing
@testable import RepositoryFeature

// A scan reports its groups as each finishes, so one can land after the user cleared the list
// or removed that group. It used to bring the group back, on screen but no longer tracked: gone
// again at the next launch, and the Settings list did not show it.
@Suite("Repository list scan membership")
@MainActor
struct RepositoryListScanMembershipTests {
	@Test("a scan landing after Clear does not bring its group back")
	func scanAfterClearIsDropped() async {
		let store = makeStore()
		store.state.$trackedRepoPaths.withLock { $0 = ["/repos/alpha"] }
		await store.send(.didScanGroup(rootPath: "/repos/alpha", rows: [mainRepo("/repos/alpha")]))
		#expect(store.state.repositoryGroups.map(\.id) == ["/repos/alpha"])

		await store.send(.view(.clearButtonTapped))
		await store.send(.didScanGroup(rootPath: "/repos/alpha", rows: [mainRepo("/repos/alpha")]))

		#expect(store.state.repositoryGroups.isEmpty)
		#expect(store.state.trackedRepoPaths.isEmpty)
	}

	@Test("a scan landing after a group's removal does not bring it back")
	func scanAfterRemovalIsDropped() async {
		let store = makeStore()
		store.state.$trackedRepoPaths.withLock { $0 = ["/repos/alpha", "/repos/beta"] }
		await store.send(.didScanGroup(rootPath: "/repos/alpha", rows: [mainRepo("/repos/alpha")]))
		await store.send(.didScanGroup(rootPath: "/repos/beta", rows: [mainRepo("/repos/beta")]))

		await store.send(.repositoryGroups(.element(id: "/repos/beta", action: .remove)))
		await store.send(.didScanGroup(rootPath: "/repos/beta", rows: [mainRepo("/repos/beta")]))

		#expect(store.state.repositoryGroups.map(\.id) == ["/repos/alpha"])
		#expect(store.state.trackedRepoPaths == ["/repos/alpha"])
	}

	@Test("a scan of a tracked repository not shown yet builds its group")
	func scanOfTrackedRepositoryBuildsGroup() async {
		let store = makeStore()
		store.state.$trackedRepoPaths.withLock { $0 = ["/repos/alpha"] }

		await store.send(.didScanGroup(rootPath: "/repos/alpha", rows: [mainRepo("/repos/alpha")]))

		#expect(store.state.repositoryGroups.map(\.id) == ["/repos/alpha"])
	}

	// MARK: - Helpers

	private func mainRepo(_ path: String) -> ScannedRepository {
		ScannedRepository(
			path: path,
			name: (path as NSString).lastPathComponent,
			directory: path,
			isWorktree: false,
			branchName: "master"
		)
	}

	/// Non-exhaustive: `repositoryGroups` and `trackedRepoPaths` are `fileprivate(set)`, so they
	/// are read back with `#expect` rather than asserted in a `send` closure.
	private func makeStore() -> TestStoreOf<RepositoryListReducer> {
		let store = TestStore(initialState: RepositoryListReducer.State()) {
			RepositoryListReducer()
		} withDependencies: {
			// `trackedRepoPaths` is file-backed; in-memory storage keeps it off the user's list.
			$0.defaultFileStorage = .inMemory
		}
		store.exhaustivity = .off
		return store
	}
}
