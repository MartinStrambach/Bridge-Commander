import ComposableArchitecture
import Foundation
import GitCore
import Testing

@testable import GitGraphFeature

// The commit menu's write actions. Git itself is stubbed (`GitCommitActionClient`); these pin down
// what is confirmed first, what reaches git, and what the graph does after: reload, tell the
// presenter, or explain the failure.
@Suite("Commit actions")
@MainActor
struct CommitActionTests {

	// MARK: - Fixtures

	private static let repositoryPath = "/tmp/repo"

	private let head = GitLogCommit(
		hash: "aaaaaaaaaaaa",
		parents: ["bbbbbbbbbbbb"],
		author: "Author",
		date: Date(timeIntervalSince1970: 1_700_000_000),
		refs: [GitCommitRef(name: "main", kind: .localBranch, isHead: true)],
		subject: "Head"
	)

	private let older = GitLogCommit(
		hash: "bbbbbbbbbbbb",
		parents: [],
		author: "Author",
		date: Date(timeIntervalSince1970: 1_600_000_000),
		refs: [],
		subject: "Older"
	)

	private func store(
		configure: (inout DependencyValues) -> Void = { _ in }
	) -> TestStoreOf<GitGraphReducer> {
		var state = GitGraphReducer.State(
			repositoryPath: Self.repositoryPath,
			repositoryName: "repo",
			worktreeBasePath: "../trees",
			worktreeCopyPaths: [".env"]
		)
		state.rows = GitGraphLayout.layout(commits: [head, older])

		let store = TestStore(initialState: state) {
			GitGraphReducer()
		} withDependencies: { [head, older] in
			$0[GitLogClient.self].loadCommits = { _, _, _ in [head, older] }
			configure(&$0)
		}
		// Alert texts are prose; the tests assert the parts that decide behavior.
		store.exhaustivity = .off(showSkippedAssertions: false)
		return store
	}

	private func receiveReload(_ store: TestStoreOf<GitGraphReducer>) async {
		await store.receive(\.commitsLoaded) {
			$0.isLoading = false
		}
	}

	// MARK: - Confirmed actions

	@Test("cherry-pick asks first, names the current branch, and runs only once confirmed")
	func cherryPickIsConfirmed() async throws {
		let applied = LockIsolated<[GitSequencerOperation]>([])
		let store = store {
			$0[GitCommitActionClient.self].apply = { operation, _, _ in
				applied.withValue { $0.append(operation) }
				return .committed
			}
		}

		await store.send(.commitAction(.cherryPickTapped(older)))
		let alert = try #require(store.state.alert)
		#expect(String(state: alert.title) == "Cherry-pick bbbbbbbb onto “main”?")
		#expect(applied.value.isEmpty)

		await store.send(.alert(.presented(.cherryPick(older)))) {
			$0.alert = nil
			$0.runningCommitAction = "Cherry-picking bbbbbbbb…"
		}
		await store.receive(\.commitAction.finished) {
			$0.runningCommitAction = nil
			$0.isLoading = true
		}
		await store.receive(\.delegate.repositoryChanged)
		await receiveReload(store)
		#expect(applied.value == [.cherryPick])
	}

	@Test("a cherry-pick stopped on conflicts offers to abort it")
	func conflictsOfferAbort() async throws {
		let aborted = LockIsolated<[GitSequencerOperation]>([])
		let store = store {
			$0[GitCommitActionClient.self].apply = { _, _, _ in .conflicts(["a.swift"]) }
			$0[GitCommitActionClient.self].abort = { operation, _ in
				aborted.withValue { $0.append(operation) }
			}
		}

		await store.send(.commitAction(.cherryPickTapped(older)))
		await store.send(.alert(.presented(.cherryPick(older))))
		await store.receive(\.commitAction.finished)
		await store.receive(\.delegate.repositoryChanged)
		await receiveReload(store)

		let alert = try #require(store.state.alert)
		#expect(alert.buttons.contains { $0.action.action == .abort(.cherryPick) })

		await store.send(.alert(.presented(.abort(.cherryPick))))
		await store.receive(\.commitAction.finished)
		await store.receive(\.delegate.repositoryChanged)
		await receiveReload(store)
		#expect(aborted.value == [.cherryPick])
	}

	@Test("a failed action explains itself and reloads nothing")
	func failureShowsAnAlert() async throws {
		let store = store {
			$0[GitCommitActionClient.self].apply = { _, _, _ in throw GitError.revertFailed("dirty tree") }
		}

		await store.send(.commitAction(.revertTapped(older)))
		await store.send(.alert(.presented(.revert(older))))
		await store.receive(\.commitAction.finished) {
			$0.runningCommitAction = nil
			$0.isLoading = false
		}

		let alert = try #require(store.state.alert)
		#expect(String(state: alert.title) == "Revert Failed")
		#expect(alert.message.map { String(state: $0) } == "Failed to revert: dirty tree")
	}

	@Test("checking out a branch needs no confirmation")
	func branchCheckoutRunsDirectly() async {
		let checkedOut = LockIsolated<[String]>([])
		let store = store {
			$0[GitCommitActionClient.self].checkoutBranch = { branch, _ in
				checkedOut.withValue { $0.append(branch) }
			}
		}

		await store.send(.commitAction(.checkoutBranchTapped("feature"))) {
			$0.runningCommitAction = "Checking out feature…"
		}
		await store.receive(\.commitAction.finished)
		await store.receive(\.delegate.repositoryChanged)
		await receiveReload(store)
		#expect(checkedOut.value == ["feature"])
	}

	@Test("while one action runs, another is ignored")
	func oneActionAtATime() async {
		let store = store {
			$0[GitCommitActionClient.self].checkoutBranch = { _, _ in
				try await Task.never()
			}
		}

		await store.send(.commitAction(.checkoutBranchTapped("feature"))) {
			$0.runningCommitAction = "Checking out feature…"
		}
		await store.send(.commitAction(.checkoutBranchTapped("other")))
		#expect(store.state.runningCommitAction == "Checking out feature…")
		await store.skipInFlightEffects()
	}

	// MARK: - Branch and worktree

	@Test("a new branch is created at the commit with the typed name, whitespace replaced")
	func newBranch() async {
		let created = LockIsolated<[String]>([])
		let store = store {
			$0[GitCommitActionClient.self].createBranch = { name, startPoint, checkout, _ in
				created.withValue { $0.append("\(name) \(startPoint) \(checkout)") }
			}
		}

		await store.send(.commitAction(.newBranchTapped(older))) {
			$0.branchForm = BranchForm(kind: .branch, commit: older)
		}
		await store.send(.commitAction(.branchFormNameChanged("fix login"))) {
			$0.branchForm?.name = "fix_login"
		}
		await store.send(.commitAction(.branchFormChecksOutChanged(false))) {
			$0.branchForm?.checksOut = false
		}
		await store.send(.commitAction(.branchFormSubmitted)) {
			$0.branchForm = nil
			$0.runningCommitAction = "Creating fix_login…"
		}
		await store.receive(\.commitAction.finished)
		await store.receive(\.delegate.repositoryChanged)
		await receiveReload(store)
		#expect(created.value == ["fix_login bbbbbbbbbbbb false"])
	}

	@Test("an empty name submits nothing")
	func emptyNameIsNotSubmitted() async {
		let store = store()

		await store.send(.commitAction(.newBranchTapped(older)))
		await store.send(.commitAction(.branchFormNameChanged("   ")))
		await store.send(.commitAction(.branchFormSubmitted))
		#expect(store.state.branchForm != nil)
		#expect(store.state.runningCommitAction == nil)
	}

	@Test("a new worktree uses the presenter's base path and copy list, and asks for a rescan")
	func newWorktree() async throws {
		let requested = LockIsolated<[String]>([])
		let folder = URL(fileURLWithPath: "/tmp/trees/repo/feature")
		let store = store {
			$0[GitCommitActionClient.self].createWorktree = { name, startPoint, _, basePath, copyPaths in
				requested.withValue { $0.append("\(name) \(startPoint) \(basePath) \(copyPaths)") }
				return GitWorktreeFromCommit(folder: folder, copyResult: nil)
			}
		}

		await store.send(.commitAction(.newWorktreeTapped(older)))
		await store.send(.commitAction(.branchFormNameChanged("feature")))
		await store.send(.commitAction(.branchFormSubmitted)) {
			$0.branchForm = nil
			$0.runningCommitAction = "Creating worktree feature…"
		}
		await store.receive(\.commitAction.finished)
		await store.receive(\.delegate.worktreeCreated)
		await receiveReload(store)

		#expect(requested.value == ["feature bbbbbbbbbbbb ../trees [\".env\"]"])
		let alert = try #require(store.state.alert)
		#expect(alert.message.map { String(state: $0) } == folder.path)
	}
}
