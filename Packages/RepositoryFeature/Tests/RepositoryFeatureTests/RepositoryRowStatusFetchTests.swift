import ComposableArchitecture
import GitActionsMenu
import GitCore
import GitHosting
import Testing
import ToolsIntegration
@testable import RepositoryFeature

// `didFetchStatus` is the one place a row learns its branch, counts and push status, and the
// one place the git menu's gating fields are derived. These pin what it writes, and — after the
// transient-failure race (rows flipping to "unknown" / "No remote") — what it must leave alone.
@Suite("Repository row status fetch")
@MainActor
struct RepositoryRowStatusFetchTests {
	// MARK: - Failed fetch

	@Test("a failed status fetch keeps the last-known branch, counts and push status")
	func failedFetchKeepsLastKnownState() async {
		var row = makeRow(branchName: "feature")
		row.unstagedChangesCount = 2
		row.stagedChangesCount = 1
		row.unpushedCommitCount = 3
		row.commitsBehindCount = 4
		row.hasRemoteBranch = true
		let store = TestStore(initialState: row) {
			RepositoryRowReducer()
		}

		// Exhaustive: any state write, or a YouTrack/PR fetch keyed on whatever the empty
		// output parsed to, fails here. Only the merge flag is forwarded to the menu.
		await store.send(.didFetchStatus(GitPorcelainStatus(parsing: "", didSucceed: false), false))
		await store.receive(\.gitActionsMenu.didCheckGitStatus)
	}

	@Test("a failed status fetch still clears a finished merge's banner")
	func failedFetchStillSyncsMergeFlag() async {
		var row = makeRow(branchName: "feature")
		row.gitActionsMenu.isMergeInProgress = true
		let store = TestStore(initialState: row) {
			RepositoryRowReducer()
		}

		await store.send(.didFetchStatus(GitPorcelainStatus(parsing: "", didSucceed: false), false))
		await store.receive(\.gitActionsMenu.didCheckGitStatus) {
			$0.gitActionsMenu.isMergeInProgress = false
		}
	}

	@Test("a status without a branch name keeps the branch the row already knew")
	func missingBranchKeepsKnownBranch() async {
		let store = makeStore(makeRow(branchName: "feature"), remote: nil)

		await store.send(.didFetchStatus(GitPorcelainStatus(parsing: "# branch.oid abc1234"), false))
		await store.finish()

		// Not "unknown", and not the repository name the row falls back to before its first fetch.
		#expect(store.state.branchName == "feature")
		#expect(store.state.gitActionsMenu.currentBranch == "feature")
	}

	// MARK: - Successful fetch

	@Test("a status fetch fills in the counts, push status and the git menu's gating fields")
	func successfulFetchPopulatesRowAndMenu() async {
		let store = makeStore(makeRow(branchName: "feature"), remote: nil)

		await store.send(.didFetchStatus(GitPorcelainStatus(parsing: Self.dirtyPorcelain), false))
		await store.finish()

		let row = store.state
		#expect(row.branchName == "feature-two")
		#expect(row.stagedChangesCount == 1)
		#expect(row.unstagedChangesCount == 2)
		#expect(row.unpushedCommitCount == 3)
		#expect(row.commitsBehindCount == 2)
		#expect(row.hasRemoteBranch == true)

		let menu = row.gitActionsMenu
		#expect(menu.currentBranch == "feature-two")
		#expect(menu.hasRemoteBranch == true)
		#expect(menu.unpushedCommitsCount == 3)
		#expect(menu.stashButton.hasChanges == true)
		#expect(menu.discardButton.hasTrackedChanges == true)
		#expect(menu.discardButton.hasUntrackedFiles == true)
	}

	@Test("only untracked files offer discarding untracked files, not tracked changes")
	func untrackedOnlyGatesDiscardActions() async {
		let store = makeStore(makeRow(branchName: "feature"), remote: nil)

		await store.send(.didFetchStatus(GitPorcelainStatus(parsing: """
		# branch.head feature
		? Scratch.swift
		"""), false))
		await store.finish()

		#expect(store.state.unstagedChangesCount == 1)
		#expect(store.state.gitActionsMenu.stashButton.hasChanges == true)
		#expect(store.state.gitActionsMenu.discardButton.hasTrackedChanges == false)
		#expect(store.state.gitActionsMenu.discardButton.hasUntrackedFiles == true)
	}

	@Test("a merge in progress zeroes the change counts and hides both discard actions")
	func mergeInProgressHidesChanges() async {
		let store = makeStore(makeRow(branchName: "feature"), remote: nil)
		// The menu polls MERGE_HEAD while a merge is in progress; a clock that never
		// advances keeps that loop parked for the length of the test.
		store.dependencies.continuousClock = TestClock()

		await store.send(.didFetchStatus(GitPorcelainStatus(parsing: Self.dirtyPorcelain), true))
		await store.receive(\.gitActionsMenu.didCheckGitStatus)
		await store.receive(\.didFetchPullRequest)

		let row = store.state
		#expect(row.stagedChangesCount == 0)
		#expect(row.unstagedChangesCount == 0)
		// Push status is not part of the conflict and still reads through.
		#expect(row.unpushedCommitCount == 3)
		#expect(row.gitActionsMenu.isMergeInProgress == true)
		#expect(row.gitActionsMenu.stashButton.hasChanges == false)
		#expect(row.gitActionsMenu.discardButton.hasTrackedChanges == false)
		#expect(row.gitActionsMenu.discardButton.hasUntrackedFiles == false)
		await store.skipInFlightEffects()
	}

	@Test("switching to another ticket's branch rebuilds the ticket button and the share text")
	func ticketChangeRebuildsTicketButton() async {
		let row = makeRow(
			branchName: "LS-1_first",
			ticketIdRegex: "[A-Z]+-\\d+",
			youtrackBaseURL: "https://youtrack.example.com"
		)
		#expect(row.ticketButton?.ticketId == "LS-1")
		let store = makeStore(row, remote: nil)
		// The button is built from the branch alone, before (and regardless of) the issue fetch.
		store.dependencies[YouTrackClient.self].fetchIssueDetails = { _, _, _ in
			throw YouTrackServiceError.httpFailure(statusCode: 500)
		}

		await store.send(.didFetchStatus(GitPorcelainStatus(parsing: "# branch.head LS-2_second"), false))
		await store.finish()

		#expect(store.state.ticketId == "LS-2")
		#expect(store.state.ticketButton?.ticketId == "LS-2")
		#expect(store.state.ticketButton?.ticketURL == "https://youtrack.example.com/issue/LS-2")
		#expect(store.state.shareButton.shareText.contains("https://youtrack.example.com/issue/LS-2"))
		#expect(!store.state.shareButton.shareText.contains("issue/LS-1"))
	}

	// MARK: - Pull request lookup on the default branch

	/// `getOriginRemote` and `fetchDetails` are left unimplemented: reaching either fails the
	/// test, which is what proves the default branch is never looked up.
	@Test("the default branch reports no PR without asking the provider", arguments: [
		(branch: "master", configured: ""),
		(branch: "main", configured: ""),
		(branch: "develop", configured: "develop"),
	])
	func defaultBranchSkipsPullRequestLookup(branch: String, configured: String) async {
		var row = makeRow(branchName: "feature", defaultBranch: configured)
		row.prUrl = "https://github.com/o/app/pull/1"
		row.prState = .ready
		let store = TestStore(initialState: row) {
			RepositoryRowReducer()
		}
		store.exhaustivity = .off

		await store.send(.didFetchStatus(GitPorcelainStatus(parsing: "# branch.head \(branch)"), false))
		await store.receive(\.didFetchPullRequest)
		await store.finish()

		#expect(store.state.prUrl == nil)
		#expect(store.state.prState == nil)
	}

	@Test("with a configured default branch, master is a feature branch and gets looked up")
	func configuredDefaultBranchLooksUpMaster() async {
		let store = makeStore(makeRow(branchName: "feature", defaultBranch: "develop"), remote: nil)
		let askedForRemote = LockIsolated(false)
		store.dependencies[GitClient.self].getOriginRemote = { _ in
			askedForRemote.setValue(true)
			return nil
		}

		await store.send(.didFetchStatus(GitPorcelainStatus(parsing: "# branch.head master"), false))
		await store.finish()

		#expect(askedForRemote.value)
	}

	// MARK: - Helpers

	/// Branch `feature-two`, 3 ahead and 2 behind its upstream, with one staged change, one
	/// unstaged change and one untracked file.
	private static let dirtyPorcelain = """
	# branch.head feature-two
	# branch.upstream origin/feature-two
	# branch.ab +3 -2
	1 M. N... 100644 100644 100644 abc1234 def5678 Sources/Staged.swift
	1 .M N... 100644 100644 100644 abc1234 def5678 Sources/App.swift
	? Untracked.swift
	"""

	private func makeRow(
		branchName: String,
		ticketIdRegex: String = "",
		defaultBranch: String = "",
		youtrackBaseURL: String = ""
	) -> RepositoryRowReducer.State {
		RepositoryRowReducer.State(
			path: "/repos/app",
			name: "app",
			branchName: branchName,
			ticketIdRegex: ticketIdRegex,
			defaultBranch: defaultBranch,
			youtrackBaseURL: youtrackBaseURL
		)
	}

	/// A non-exhaustive store whose PR lookup stops at the origin remote (`nil` = no remote).
	private func makeStore(
		_ row: RepositoryRowReducer.State,
		remote: GitRemote?
	) -> TestStoreOf<RepositoryRowReducer> {
		let store = TestStore(initialState: row) {
			RepositoryRowReducer()
		} withDependencies: {
			$0[GitClient.self].getOriginRemote = { _ in remote }
		}
		store.exhaustivity = .off
		return store
	}
}
