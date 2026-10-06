import ComposableArchitecture
import Foundation
import GitCore
import GitHosting
import Testing
import ToolsIntegration
@testable import RepositoryFeature

// A change on disk can arrive on every saved file, so the row re-reads git status for it but
// asks YouTrack and the PR provider only when the branch or its upstream moved. Their clients
// are left unimplemented wherever a lookup must not happen: reaching one fails the test.
@Suite("Repository changes on disk")
@MainActor
struct RepositoryChangedOnDiskTests {
	// MARK: - Row

	@Test("an edit updates the counts without asking the network")
	func editOnSameBranchSkipsLookups() async {
		let store = makeRowStore(knownStatus)

		await store.send(.didFetchStatusAfterChangeOnDisk(GitPorcelainStatus(parsing: """
		# branch.head feature
		# branch.upstream origin/feature
		# branch.ab +1 -0
		1 .M N... 100644 100644 100644 abc1234 def5678 Sources/App.swift
		"""), false))
		await store.finish()

		#expect(store.state.unstagedChangesCount == 1)
	}

	@Test("a local commit only adds to the unpushed count and asks nothing")
	func localCommitSkipsLookups() async {
		let store = makeRowStore(knownStatus)

		await store.send(.didFetchStatusAfterChangeOnDisk(GitPorcelainStatus(parsing: """
		# branch.head feature
		# branch.upstream origin/feature
		# branch.ab +2 -0
		"""), false))
		await store.finish()

		#expect(store.state.unpushedCommitCount == 2)
	}

	@Test("a checkout looks up the new branch's PR and its stash")
	func checkoutLooksUpNewBranch() async {
		let store = makeRowStore(knownStatus)
		let askedForRemote = LockIsolated(false)
		store.dependencies[GitClient.self].getOriginRemote = { _ in
			askedForRemote.setValue(true)
			return nil
		}

		await store.send(.didFetchStatusAfterChangeOnDisk(GitPorcelainStatus(parsing: "# branch.head other"), false))
		await store.receive(\.gitActionsMenu.refresh)
		await store.finish()

		#expect(store.state.branchName == "other")
		#expect(askedForRemote.value)
	}

	@Test("a push, fetch or pull looks up the PR again", arguments: [
		// Pushed: nothing left unpushed.
		"# branch.head feature\n# branch.upstream origin/feature\n# branch.ab +0 -0",
		// Fetched: the remote moved ahead.
		"# branch.head feature\n# branch.upstream origin/feature\n# branch.ab +1 -3",
		// The upstream branch went away.
		"# branch.head feature",
	])
	func upstreamMoveLooksUpPullRequest(porcelain: String) async {
		let store = makeRowStore(knownStatus)
		let askedForRemote = LockIsolated(false)
		store.dependencies[GitClient.self].getOriginRemote = { _ in
			askedForRemote.setValue(true)
			return nil
		}

		await store.send(.didFetchStatusAfterChangeOnDisk(GitPorcelainStatus(parsing: porcelain), false))
		await store.finish()

		#expect(askedForRemote.value)
	}

	@Test("a stash change refreshes only the stash, without running git status")
	func stashChangeSkipsStatus() async {
		let store = makeRowStore(knownStatus)

		await store.send(.changedOnDisk(.stash))
		await store.receive(\.gitActionsMenu.refresh)
		await store.finish()
	}

	@Test("a status change re-reads git status")
	func statusChangeFetchesStatus() async {
		let store = makeRowStore(knownStatus)
		store.dependencies[GitClient.self].getCurrentBranch = { _ in
			GitPorcelainStatus(parsing: "", didSucceed: false)
		}

		await store.send(.changedOnDisk(.status))
		await store.receive(\.didFetchStatusAfterChangeOnDisk)
		await store.finish()
	}

	// MARK: - List

	@Test("a finished scan watches every row, and a rescan of the same rows keeps the watch")
	func scanStartsWatchOnce() async {
		let (changes, _) = AsyncStream<[GitRepositoryChange]>.makeStream()
		let watched = LockIsolated<[[String]]>([])
		let store = makeListStore(changes: changes, watched: watched)

		await scanAlpha(store)
		await store.send(.scanCompleted)
		await waitUntil { !watched.value.isEmpty }
		await scanAlpha(store)
		await store.send(.scanCompleted)

		#expect(store.state.watchedRepositoryPaths == ["/repos/alpha", "/repos/alpha-one"])
		await store.send(.view(.onDisappear))
		await store.finish()
		#expect(watched.value == [["/repos/alpha", "/repos/alpha-one"]])
	}

	@Test("a change reaches the row it belongs to")
	func changeIsRoutedToItsRow() async {
		let (changes, continuation) = AsyncStream<[GitRepositoryChange]>.makeStream()
		let store = makeListStore(changes: changes, watched: LockIsolated([]))

		await scanAlpha(store)
		await store.send(.scanCompleted)
		continuation.yield([GitRepositoryChange(repositoryPath: "/repos/alpha-one", kinds: [.status, .stash])])

		await store.receive(\.repositoriesChangedOnDisk)
		await store.receive {
			guard
				case let .repositoryGroups(.element(
					id: "/repos/alpha",
					action: .worktrees(.element(id: "/repos/alpha-one", action: .changedOnDisk(kinds)))
				)) = $0
			else {
				return false
			}
			return kinds == [.status, .stash]
		}

		await store.send(.view(.onDisappear))
		await store.finish()
	}

	@Test("a worktree added in a terminal rescans its group")
	func worktreeListChangeRescansGroup() async {
		let (changes, continuation) = AsyncStream<[GitRepositoryChange]>.makeStream()
		let store = makeListStore(changes: changes, watched: LockIsolated([]))

		await scanAlpha(store)
		await store.send(.scanCompleted)
		continuation.yield([GitRepositoryChange(repositoryPath: "/repos/alpha", kinds: .worktreeList)])

		await store.receive(\.repositoriesChangedOnDisk)
		await store.receive(\.didScanGroup)

		await store.send(.view(.onDisappear))
		await store.finish()
	}

	@Test("a change for a repository the list no longer has is dropped")
	func changeForUnknownRepositoryIsDropped() async {
		let store = makeListStore(changes: AsyncStream { $0.finish() }, watched: LockIsolated([]))
		store.exhaustivity = .on

		await store.send(.repositoriesChangedOnDisk([
			GitRepositoryChange(repositoryPath: "/repos/gone", kinds: [.status, .worktreeList]),
		]))
	}

	// MARK: - Helpers

	/// Branch `feature`, one commit ahead of `origin/feature`, nothing behind.
	private var knownStatus: RepositoryRowReducer.State {
		var row = RepositoryRowReducer.State(path: "/repos/app", name: "app", branchName: "feature")
		row.hasRemoteBranch = true
		row.unpushedCommitCount = 1
		row.commitsBehindCount = 0
		return row
	}

	/// Non-exhaustive; every git, YouTrack and PR client is unimplemented unless a test stubs it.
	private func makeRowStore(_ row: RepositoryRowReducer.State) -> TestStoreOf<RepositoryRowReducer> {
		let store = TestStore(initialState: row) {
			RepositoryRowReducer()
		}
		store.exhaustivity = .off
		return store
	}

	private func makeListStore(
		changes: AsyncStream<[GitRepositoryChange]>,
		watched: LockIsolated<[[String]]>
	) -> TestStoreOf<RepositoryListReducer> {
		let store = TestStore(initialState: RepositoryListReducer.State()) {
			RepositoryListReducer()
		} withDependencies: {
			$0[GitRepositoryWatcherClient.self].changes = { paths in
				watched.withValue { $0.append(paths) }
				return changes
			}
			// Rows routed a change fan out into git lookups of their own; stub the leaves.
			$0[GitClient.self].getCurrentBranch = { _ in
				GitPorcelainStatus(parsing: "", didSucceed: false)
			}
			$0[XcodeClient.self].findXcodeProject = { _, _, _ in nil }
		}
		store.exhaustivity = .off
		return store
	}

	/// The watch starts in an effect, which may not have run by the time `send` returns.
	private func waitUntil(_ condition: () -> Bool) async {
		for _ in 0 ..< 200 where !condition() {
			try? await Task.sleep(for: .milliseconds(10))
		}
	}

	private func scanAlpha(_ store: TestStoreOf<RepositoryListReducer>) async {
		await store.send(.didScanGroup(rootPath: "/repos/alpha", rows: [
			ScannedRepository(
				path: "/repos/alpha",
				name: "alpha",
				directory: "/repos/alpha",
				isWorktree: false,
				branchName: "master"
			),
			ScannedRepository(
				path: "/repos/alpha-one",
				name: "alpha-one",
				directory: "/repos/alpha-one",
				isWorktree: true,
				branchName: "feature-one"
			),
		]))
	}
}
