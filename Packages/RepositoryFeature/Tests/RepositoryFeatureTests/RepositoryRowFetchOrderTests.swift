import ComposableArchitecture
import GitCore
import GitHosting
import Testing
import ToolsIntegration
@testable import RepositoryFeature

// A row asks the PR provider and YouTrack after every status read, and those answers come back
// in whatever order the network returns them. A periodic refresh asking about branch A, then a
// checkout of B, must not end with A's slow answer written over B's — the stale state
// `applyStatus` clears on a branch change.
@Suite("Repository row fetch order")
@MainActor
struct RepositoryRowFetchOrderTests {
	@Test("a slow PR answer for the branch the row left does not overwrite the new branch's")
	func slowPullRequestForPreviousBranchIsDropped() async {
		let clock = TestClock()
		let store = makeStore(row: makeRow(branchName: "feature-a"), clock: clock) { branch in
			if branch == "feature-a" {
				try await clock.sleep(for: .seconds(10))
			}
			return Self.pullRequest(number: branch == "feature-a" ? 1 : 2, pipeline: .running)
		}

		await store.send(.didFetchStatus(GitPorcelainStatus(parsing: "# branch.head feature-a"), false))
		await store.send(.didFetchStatusAfterChangeOnDisk(GitPorcelainStatus(parsing: "# branch.head feature-b"), false))
		await store.receive(\.didFetchPullRequest)
		#expect(store.state.prUrl == Self.pullRequest(number: 2).url)

		await clock.advance(by: .seconds(10))
		await store.finish()
		await store.skipReceivedActions(strict: false)

		#expect(store.state.branchName == "feature-b")
		#expect(store.state.prUrl == Self.pullRequest(number: 2).url)
	}

	@Test("of two refreshes on the same branch, the older PR answer never lands after the newer")
	func olderPullRequestAnswerOnSameBranchIsDropped() async {
		let clock = TestClock()
		let calls = LockIsolated(0)
		let store = makeStore(row: makeRow(branchName: "feature-a"), clock: clock) { _ in
			let call = calls.withValue { $0 += 1; return $0 }
			if call == 1 {
				try await clock.sleep(for: .seconds(10))
				return Self.pullRequest(number: 1, pipeline: .running)
			}
			return Self.pullRequest(number: 1, pipeline: .success)
		}

		await store.send(.didFetchStatus(GitPorcelainStatus(parsing: "# branch.head feature-a"), false))
		await store.send(.didFetchStatus(GitPorcelainStatus(parsing: "# branch.head feature-a"), false))
		await store.receive(\.didFetchPullRequest)
		#expect(store.state.pipelineState == .success)

		await clock.advance(by: .seconds(10))
		await store.finish()
		await store.skipReceivedActions(strict: false)

		#expect(store.state.pipelineState == .success)
	}

	@Test("a slow YouTrack answer for the ticket the row left does not overwrite the new ticket's")
	func slowYouTrackForPreviousTicketIsDropped() async {
		let clock = TestClock()
		let row = makeRow(
			branchName: "LS-1_first",
			ticketIdRegex: "[A-Z]+-\\d+",
			youtrackBaseURL: "https://youtrack.example.com"
		)
		let store = makeStore(row: row, clock: clock) { _ in nil }
		store.dependencies[YouTrackClient.self].fetchIssueDetails = { ticketId, _, _ in
			if ticketId == "LS-1" {
				try await clock.sleep(for: .seconds(10))
				return Self.issue(state: .done)
			}
			return Self.issue(state: .inProgress)
		}

		await store.send(.didFetchStatus(GitPorcelainStatus(parsing: "# branch.head LS-1_first"), false))
		await store.send(.didFetchStatusAfterChangeOnDisk(GitPorcelainStatus(parsing: "# branch.head LS-2_second"), false))
		await store.receive(\.didFetchYouTrack)
		#expect(store.state.ticketState == .inProgress)

		await clock.advance(by: .seconds(10))
		await store.finish()
		await store.skipReceivedActions(strict: false)

		#expect(store.state.ticketId == "LS-2")
		#expect(store.state.ticketState == .inProgress)
	}

	/// A rescan writes the branch it found without fetching anything, so an answer still in flight
	/// for the old branch is not cancelled by a newer fetch. Its key is what keeps it out.
	@Test("an answer about a branch or ticket the row is not on is dropped")
	func answerForAnotherKeyIsDropped() async {
		let store = TestStore(initialState: makeRow(
			branchName: "LS-2_second",
			ticketIdRegex: "[A-Z]+-\\d+",
			youtrackBaseURL: "https://youtrack.example.com"
		)) {
			RepositoryRowReducer()
		}

		// Exhaustive: any state write fails here.
		await store.send(.didFetchPullRequest(Self.pullRequest(number: 1), branch: "LS-1_first"))
		await store.send(.didFetchPullRequestFailed("GitHub PR fetch failed: HTTP 500", branch: "LS-1_first"))
		await store.send(.didFetchYouTrack(Self.issue(state: .done), ticketId: "LS-1"))
	}

	// MARK: - Helpers

	private nonisolated static func pullRequest(number: Int, pipeline: PipelineState = .running) -> PullRequestDetails {
		PullRequestDetails(
			url: "https://github.com/o/app/pull/\(number)",
			state: .ready,
			provider: .github,
			pipeline: PipelineStatus(state: pipeline, url: "https://github.com/o/app/actions/runs/\(number)")
		)
	}

	private nonisolated static func issue(state: TicketState) -> IssueDetails {
		IssueDetails(
			androidCR: nil,
			iosCR: nil,
			androidReviewerName: nil,
			iosReviewerName: nil,
			ticketState: state,
			stateFieldId: nil,
			stateTransitions: []
		)
	}

	private func makeRow(
		branchName: String,
		ticketIdRegex: String = "",
		youtrackBaseURL: String = ""
	) -> RepositoryRowReducer.State {
		RepositoryRowReducer.State(
			path: "/repos/app",
			name: "app",
			branchName: branchName,
			ticketIdRegex: ticketIdRegex,
			youtrackBaseURL: youtrackBaseURL
		)
	}

	/// A non-exhaustive store whose PR provider answers with `fetchDetails`.
	private func makeStore(
		row: RepositoryRowReducer.State,
		clock: TestClock<Duration>,
		fetchDetails: @escaping @Sendable (_ branch: String) async throws -> PullRequestDetails?
	) -> TestStoreOf<RepositoryRowReducer> {
		let store = TestStore(initialState: row) {
			RepositoryRowReducer()
		} withDependencies: {
			$0.continuousClock = clock
			$0[GitClient.self].getOriginRemote = { _ in GitRemote(host: "github.com", owner: "o", repo: "app") }
			$0[PullRequestClient.self].fetchDetails = { _, branch in try await fetchDetails(branch) }
		}
		store.exhaustivity = .off
		return store
	}
}
