import ComposableArchitecture
import Foundation
import GitCore
import Testing
import ToolsIntegration
@testable import RepositoryFeature

// Covers manual reordering of the repository list: what a drop does to the on-screen order,
// what it writes to `trackedRepoPaths` — which is both the persisted order and what a relaunch
// restores from — and which drops are refused.
//
// The drag itself is not covered here and cannot be: whether a drop is delivered at all depends
// on AppKit specifics of a `List` section header (see `RepoGroupView.reorderable`), which no unit
// test observes. These tests start where the view hands the dragged path to the reducer.
@Suite("Repository list manual reordering")
@MainActor
struct RepositoryListReorderTests {
	// MARK: - Reordering

	@Test("a repository dropped on the one above it takes that one's place")
	func dropOnEarlierRepositoryMovesItUp() async {
		let store = makeStore()
		await addRepositories(["/repos/alpha", "/repos/beta", "/repos/gamma"], to: store)

		await drop("/repos/gamma", onto: "/repos/alpha", in: store)

		#expect(store.state.repositoryGroups.map(\.id) == [
			"/repos/gamma", "/repos/alpha", "/repos/beta",
		])
		await store.finish()
	}

	@Test("a repository dropped on the one below it takes that one's place")
	func dropOnLaterRepositoryMovesItDown() async {
		let store = makeStore()
		await addRepositories(["/repos/alpha", "/repos/beta", "/repos/gamma"], to: store)

		// Dragging downward, the target shifts up rather than the dragged repo landing after it —
		// so alpha ends up where beta was, not past it.
		await drop("/repos/alpha", onto: "/repos/beta", in: store)

		#expect(store.state.repositoryGroups.map(\.id) == [
			"/repos/beta", "/repos/alpha", "/repos/gamma",
		])
		await store.finish()
	}

	@Test("reordering carries the repository's worktrees with it")
	func reorderKeepsWorktreesWithTheirRepository() async {
		let store = makeStore()
		await addRepositories(["/repos/alpha"], to: store)
		await addRepository(
			"/repos/beta",
			scanned: [
				mainRepo("/repos/beta", name: "beta"),
				worktree("/repos/beta-one", name: "beta-one", branch: "feature-one"),
				worktree("/repos/beta-two", name: "beta-two", branch: "feature-two"),
			],
			to: store
		)

		await drop("/repos/beta", onto: "/repos/alpha", in: store)

		#expect(store.state.repositoryGroups.map(\.id) == ["/repos/beta", "/repos/alpha"])
		#expect(store.state.repositoryGroups[id: "/repos/beta"]?.worktrees.count == 2)
		await store.finish()
	}

	// MARK: - Persistence

	@Test("the new order is written to the tracked paths a relaunch restores from")
	func reorderPersistsTheOnScreenOrder() async {
		let store = makeStore()
		await addRepositories(["/repos/alpha", "/repos/beta", "/repos/gamma"], to: store)

		await drop("/repos/gamma", onto: "/repos/beta", in: store)

		#expect(store.state.trackedRepoPaths == ["/repos/alpha", "/repos/gamma", "/repos/beta"])
		#expect(store.state.trackedRepoPaths == store.state.repositoryGroups.map(\.id))
		await store.finish()
	}

	@Test("a tracked repository with no group keeps its place instead of being dropped")
	func reorderKeepsUntrackedGroupsInThePersistedList() async {
		let store = makeStore()
		await addRepositories(["/repos/alpha", "/repos/beta"], to: store)
		// A repo that is tracked but produced no group this launch — a scan that came back empty,
		// e.g. a repository that has been moved on disk. It must survive a reorder, or the next
		// launch silently forgets it.
		store.exhaustivity = .off
		await store.send(.addRepositorySucceeded(rootPath: "/repos/missing", scanned: []))
		store.exhaustivity = .on
		#expect(store.state.repositoryGroups.map(\.id) == ["/repos/alpha", "/repos/beta"])

		await drop("/repos/beta", onto: "/repos/alpha", in: store)

		#expect(store.state.trackedRepoPaths == ["/repos/beta", "/repos/alpha", "/repos/missing"])
		await store.finish()
	}

	// MARK: - Refused drops

	@Test("dropping a repository on itself changes nothing")
	func dropOnItselfIsANoOp() async {
		let store = makeStore()
		await addRepositories(["/repos/alpha", "/repos/beta"], to: store)

		// Exhaustive from here: any state change fails the send below.
		await store.send(.view(.repositoryGroupDropped(
			draggedPath: "/repos/alpha",
			ontoPath: "/repos/alpha"
		)))
		await store.finish()
	}

	@Test("a dropped path that names no repository is ignored")
	func dropOfUnknownPathIsANoOp() async {
		let store = makeStore()
		await addRepositories(["/repos/alpha", "/repos/beta"], to: store)

		// The payload is plain text, so anything draggable in any app can land on a header —
		// including text that looks nothing like a tracked repository.
		await store.send(.view(.repositoryGroupDropped(
			draggedPath: "just some dragged text",
			ontoPath: "/repos/alpha"
		)))
		await store.send(.view(.repositoryGroupDropped(
			draggedPath: "/repos/alpha",
			ontoPath: "/repos/not-tracked"
		)))
		await store.finish()
	}

	// MARK: - Order across scans

	@Test("repositories keep the order they were added in, not alphabetical order")
	func groupsFollowTrackedOrderRatherThanName() async {
		let store = makeStore()
		// Added out of alphabetical order on purpose: a repo lands at the end when added and
		// moves only when dragged.
		await addRepositories(["/repos/gamma", "/repos/alpha", "/repos/beta"], to: store)

		#expect(store.state.repositoryGroups.map(\.id) == [
			"/repos/gamma", "/repos/alpha", "/repos/beta",
		])
		await store.finish()
	}

	@Test("a manual order survives a rescan that reports groups in a different order")
	func rescanRestoresTheManualOrder() async {
		let store = makeStore()
		await addRepositories(["/repos/alpha", "/repos/beta", "/repos/gamma"], to: store)
		await drop("/repos/gamma", onto: "/repos/alpha", in: store)
		#expect(store.state.trackedRepoPaths.first == "/repos/gamma")

		// A full scan runs its groups in parallel and reports them as each finishes, so the
		// arrival order is arbitrary — here the exact reverse of the manual one. Re-scanning an
		// existing group merges into it in place, so drive the ordering path that a fresh launch
		// takes: drop the groups, then let the scan rebuild them.
		store.exhaustivity = .off
		await store.send(.view(.clearButtonTapped))
		store.state.$trackedRepoPaths.withLock {
			$0 = ["/repos/gamma", "/repos/alpha", "/repos/beta"]
		}
		for path in ["/repos/beta", "/repos/alpha", "/repos/gamma"] {
			await store.send(.didScanGroup(
				rootPath: path,
				rows: [mainRepo(path, name: (path as NSString).lastPathComponent)]
			))
		}

		#expect(store.state.repositoryGroups.map(\.id) == [
			"/repos/gamma", "/repos/alpha", "/repos/beta",
		])
		await store.finish()
	}

	// MARK: - Helpers

	private func makeStore() -> TestStoreOf<RepositoryListReducer> {
		TestStore(initialState: RepositoryListReducer.State()) {
			RepositoryListReducer()
		} withDependencies: {
			// `trackedRepoPaths` is file-backed, and these tests both read and write it. In-memory
			// storage keeps them off the real list in Application Support — which is the user's.
			$0.defaultFileStorage = .inMemory
			// A row refresh fans out to git and Xcode lookups of its own; none of that is under
			// test here. A failed status short-circuits the row's follow-up fetches.
			$0[GitClient.self].getCurrentBranch = { _ in
				GitPorcelainStatus(parsing: "", didSucceed: false)
			}
			$0[XcodeClient.self].findXcodeProject = { _, _, _ in nil }
			$0[LastOpenedDirectoryClient.self].load = { nil }
		}
	}

	/// Sends a drop and leaves exhaustivity off: the reducer mutates `repositoryGroups` and
	/// `trackedRepoPaths`, which are `fileprivate(set)` and so cannot be asserted from a `send`
	/// closure here. Each test reads the result back with `#expect` instead. The tests where
	/// *nothing* may change stay exhaustive and send directly.
	private func drop(
		_ draggedPath: String,
		onto ontoPath: String,
		in store: TestStoreOf<RepositoryListReducer>
	) async {
		store.exhaustivity = .off
		await store.send(.view(.repositoryGroupDropped(
			draggedPath: draggedPath,
			ontoPath: ontoPath
		)))
	}

	/// Adds each repository as one plain group, in the order given — the same route the "add
	/// repository" button takes, so `trackedRepoPaths` ends up in that order too.
	private func addRepositories(
		_ paths: [String],
		to store: TestStoreOf<RepositoryListReducer>
	) async {
		for path in paths {
			let name = (path as NSString).lastPathComponent
			await addRepository(path, scanned: [mainRepo(path, name: name)], to: store)
		}
	}

	private func addRepository(
		_ path: String,
		scanned: [ScannedRepository],
		to store: TestStoreOf<RepositoryListReducer>
	) async {
		// Non-exhaustive only while arranging: the rows kicked off by a new group fan out into
		// effects of their own, and each test turns exhaustivity back on for the drop itself.
		store.exhaustivity = .off
		await store.send(.addRepositorySucceeded(rootPath: path, scanned: scanned))
		store.exhaustivity = .on
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
