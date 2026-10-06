import ComposableArchitecture
import Foundation
import GitCore
import GitActionsMenu
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

	@Test("a stash change alongside a status change is checked once, after the status lands")
	func stashWithStatusIsCheckedAfterStatus() async {
		// The menu already mirrors the push status, so the status read changes nothing but the flag.
		var row = knownStatus
		row.gitActionsMenu.hasRemoteBranch = true
		row.gitActionsMenu.unpushedCommitsCount = 1
		let store = TestStore(initialState: row) {
			RepositoryRowReducer()
		} withDependencies: {
			$0[GitClient.self].getCurrentBranch = { _ in
				GitPorcelainStatus(parsing: "# branch.head feature\n# branch.upstream origin/feature\n# branch.ab +1 -0")
			}
		}

		// Exhaustive: a stash check sent alongside the status read, or a second one after it, fails.
		await store.send(.changedOnDisk([.status, .stash])) {
			$0.isStashCheckPending = true
		}
		await store.receive(\.didFetchStatusAfterChangeOnDisk) {
			$0.isStashCheckPending = false
		}
		await store.receive(\.gitActionsMenu.didCheckGitStatus)
		await store.receive(\.gitActionsMenu.refresh)
		store.exhaustivity = .off
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

	@Test("a newer change cancels a status fetch still running, so an older snapshot cannot land last")
	func newerChangeSupersedesRunningFetch() async {
		let store = makeRowStore(knownStatus)
		let calls = LockIsolated(0)
		store.dependencies[GitClient.self].getCurrentBranch = slowThenFast(calls: calls, fast: """
		# branch.head feature
		# branch.upstream origin/feature
		# branch.ab +1 -0
		1 .M N... 100644 100644 100644 abc1234 def5678 Sources/App.swift
		""")

		await store.send(.changedOnDisk(.status))
		await waitUntil { calls.value == 1 }
		await store.send(.changedOnDisk(.status))
		await store.receive(\.didFetchStatusAfterChangeOnDisk)
		await store.finish()
		// Brings `store.state` up to whatever arrived after the `receive`, a stale result included.
		await store.skipReceivedActions()

		// The first fetch's stale branch never lands, even once its `git status` is killed.
		#expect(store.state.branchName == "feature")
		#expect(store.state.unstagedChangesCount == 1)
	}

	@Test("a change that cancels a refresh's status fetch still asks what the refresh would have")
	func changeSupersedingRefreshKeepsItsLookups() async {
		let store = makeRowStore(knownStatus)
		// Same branch, same upstream: on its own, a change on disk would ask nothing.
		let calls = LockIsolated(0)
		store.dependencies[GitClient.self].getCurrentBranch = slowThenFast(calls: calls, fast: """
		# branch.head feature
		# branch.upstream origin/feature
		# branch.ab +1 -0
		""")
		let askedForRemote = LockIsolated(false)
		store.dependencies[GitClient.self].getOriginRemote = { _ in
			askedForRemote.setValue(true)
			return nil
		}
		store.dependencies[XcodeClient.self].findXcodeProject = { _, _, _ in nil }

		await store.send(.refresh)
		await waitUntil { calls.value == 1 }
		await store.send(.changedOnDisk(.status))
		await store.receive(\.didFetchStatus)
		await store.finish()
		// Brings `store.state` up to whatever arrived after the `receive`, a stale result included.
		await store.skipReceivedActions()

		#expect(askedForRemote.value)
		#expect(store.state.branchName == "feature")
		#expect(!store.state.isRefreshingStatus)
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

	@Test("a rescan that finds a new worktree watches it too")
	func rescanWithNewRowRestartsWatch() async {
		let (changes, _) = AsyncStream<[GitRepositoryChange]>.makeStream()
		let watched = LockIsolated<[[String]]>([])
		let store = makeListStore(changes: changes, watched: watched)

		await scanAlpha(store)
		await store.send(.scanCompleted)
		await waitUntil { watched.value.count == 1 }
		await scanAlpha(store, extraWorktree: "/repos/alpha-two")
		await store.send(.scanCompleted)
		await waitUntil { watched.value.count == 2 }

		#expect(watched.value == [
			["/repos/alpha", "/repos/alpha-one"],
			["/repos/alpha", "/repos/alpha-one", "/repos/alpha-two"],
		])
		await store.send(.view(.onDisappear))
		await store.finish()
	}

	@Test("removing a group stops watching its rows, and removing the last one stops the watch")
	func removingGroupsRepointsWatch() async {
		let (changes, _) = AsyncStream<[GitRepositoryChange]>.makeStream()
		let watched = LockIsolated<[[String]]>([])
		let store = makeListStore(changes: changes, watched: watched)

		await scanAlpha(store)
		await store.send(.didScanGroup(rootPath: "/repos/beta", rows: [
			ScannedRepository(
				path: "/repos/beta",
				name: "beta",
				directory: "/repos/beta",
				isWorktree: false,
				branchName: "main"
			),
		]))
		await store.send(.scanCompleted)
		await waitUntil { watched.value.count == 1 }

		await store.send(.repositoryGroups(.element(id: "/repos/alpha", action: .remove)))
		await waitUntil { watched.value.count == 2 }
		#expect(watched.value.last == ["/repos/beta"])

		// The last group gone: the watch is cancelled, not restarted over nothing.
		await store.send(.repositoryGroups(.element(id: "/repos/beta", action: .remove)))
		#expect(store.state.watchedRepositoryPaths.isEmpty)
		await store.finish()
		#expect(watched.value.count == 2)
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

	@Test("a stash change in the terminal's repository reaches the toolbar's git menu too")
	func stashChangeRefreshesTerminalGitMenu() async {
		let store = makeListStore(
			terminalOpen(on: "/repos/alpha-one"),
			changes: AsyncStream { $0.finish() },
			watched: LockIsolated([])
		)

		await scanAlpha(store)
		await store.send(.repositoriesChangedOnDisk([
			GitRepositoryChange(repositoryPath: "/repos/alpha-one", kinds: .stash),
		]))

		await store.receive(\.terminalLayout.gitActionsMenu.refresh)
		await store.finish()
	}

	@Test("a stash change in another repository leaves the toolbar's git menu alone")
	func stashChangeElsewhereLeavesTerminalGitMenu() async {
		let store = makeListStore(
			terminalOpen(on: "/repos/alpha-one"),
			changes: AsyncStream { $0.finish() },
			watched: LockIsolated([])
		)
		await scanAlpha(store)

		// Exhaustive from here: the row's own stash check is all the change may cause.
		store.exhaustivity = .on
		await store.send(.repositoriesChangedOnDisk([
			GitRepositoryChange(repositoryPath: "/repos/alpha", kinds: .stash),
		]))
		await store.receive(\.repositoryGroups[id: "/repos/alpha"].header.changedOnDisk)
		await store.receive(\.repositoryGroups[id: "/repos/alpha"].header.gitActionsMenu.refresh)
		await store.receive(\.repositoryGroups[id: "/repos/alpha"].header.gitActionsMenu.stashButton.checkStashStatus)
		await store.receive(\.repositoryGroups[id: "/repos/alpha"].header.gitActionsMenu.stashButton.didFindStash)
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

	/// The terminal panel open on `path`, its toolbar showing that repository's git menu.
	private func terminalOpen(on path: String) -> RepositoryListReducer.State {
		var state = RepositoryListReducer.State()
		var layout = TerminalLayoutReducer.State(activeRepositoryPath: path)
		layout.gitActionsMenu = GitActionsMenuReducer.State(repositoryPath: path, currentBranch: "feature-one")
		state.terminalLayout = layout
		return state
	}

	/// Branch `feature`, one commit ahead of `origin/feature`, nothing behind.
	private var knownStatus: RepositoryRowReducer.State {
		var row = RepositoryRowReducer.State(path: "/repos/app", name: "app", branchName: "feature")
		row.hasRemoteBranch = true
		row.unpushedCommitCount = 1
		row.commitsBehindCount = 0
		row.hasFetchedStatus = true
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
		_ initialState: RepositoryListReducer.State = RepositoryListReducer.State(),
		changes: AsyncStream<[GitRepositoryChange]>,
		watched: LockIsolated<[[String]]>
	) -> TestStoreOf<RepositoryListReducer> {
		let store = TestStore(initialState: initialState) {
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

	/// A `getCurrentBranch` whose first call is the slow one: it answers a stale branch only after
	/// a later call has answered `fast`, so unless it is cancelled its result lands last.
	private func slowThenFast(
		calls: LockIsolated<Int>,
		fast: String
	) -> @Sendable (String) async -> GitPorcelainStatus {
		let fastAnswered = LockIsolated(false)
		return { _ in
			let call = calls.withValue { count in
				count += 1
				return count
			}
			guard call == 1 else {
				fastAnswered.setValue(true)
				return GitPorcelainStatus(parsing: fast)
			}

			// Cancellation ends the wait early, as killing `git status` would.
			do {
				while !fastAnswered.value {
					try await Task.sleep(for: .milliseconds(10))
				}
				// Give the fast answer time to reach the reducer first.
				try await Task.sleep(for: .milliseconds(50))
			}
			catch {}
			return GitPorcelainStatus(parsing: "# branch.head stale")
		}
	}

	/// The watch starts in an effect, which may not have run by the time `send` returns.
	private func waitUntil(_ condition: () -> Bool) async {
		for _ in 0 ..< 200 where !condition() {
			try? await Task.sleep(for: .milliseconds(10))
		}
	}

	private func scanAlpha(_ store: TestStoreOf<RepositoryListReducer>, extraWorktree: String? = nil) async {
		let extra = extraWorktree.map { path in
			ScannedRepository(
				path: path,
				name: (path as NSString).lastPathComponent,
				directory: path,
				isWorktree: true,
				branchName: "feature-two"
			)
		}
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
		] + (extra.map { [$0] } ?? [])))
	}
}
