import ComposableArchitecture
import GitCore
import GitHosting
import Testing
@testable import RepositoryFeature

@Suite("Repository row pull request state")
struct RepositoryRowPullRequestTests {
	private func makeRow() -> RepositoryRowReducer.State {
		RepositoryRowReducer.State(
			path: "/repos/app",
			name: "app",
			branchName: "LS-1234_feature"
		)
	}

	@MainActor
	private func makeStore(state: RepositoryRowReducer.State) -> TestStoreOf<RepositoryRowReducer> {
		let store = TestStore(initialState: state) {
			RepositoryRowReducer()
		}
		store.exhaustivity = .off
		return store
	}

	@Test("an open PR populates all fields including the unresolved discussion count")
	@MainActor
	func openPullRequestPopulatesState() async {
		let store = makeStore(state: makeRow())

		let details = PullRequestDetails(
			url: "https://gitlab.com/g/app/-/merge_requests/7",
			state: .ready,
			provider: .gitlab,
			pipeline: PipelineStatus(state: .running, url: "https://gitlab.com/g/app/-/pipelines/42"),
			unresolvedDiscussionsCount: 3
		)
		await store.send(.didFetchPullRequest(details))

		#expect(store.state.prUrl == "https://gitlab.com/g/app/-/merge_requests/7")
		#expect(store.state.prState == .ready)
		#expect(store.state.prProvider == .gitlab)
		#expect(store.state.pipelineState == .running)
		#expect(store.state.pipelineUrl == "https://gitlab.com/g/app/-/pipelines/42")
		#expect(store.state.prUnresolvedDiscussions == 3)
	}

	@Test("a draft PR still surfaces the unresolved discussion count")
	@MainActor
	func draftPullRequestKeepsCount() async {
		let store = makeStore(state: makeRow())

		await store.send(.didFetchPullRequest(PullRequestDetails(
			url: "https://github.com/o/app/pull/7",
			state: .draft,
			provider: .github,
			unresolvedDiscussionsCount: 2
		)))

		#expect(store.state.prUnresolvedDiscussions == 2)
	}

	@Test("merged and closed PRs hide the unresolved discussion count")
	@MainActor
	func mergedAndClosedHideCount() async {
		for state in [PullRequestState.merged, .closed] {
			var row = makeRow()
			row.prUnresolvedDiscussions = 3
			let store = makeStore(state: row)

			await store.send(.didFetchPullRequest(PullRequestDetails(
				url: "https://gitlab.com/g/app/-/merge_requests/7",
				state: state,
				provider: .gitlab,
				unresolvedDiscussionsCount: 3
			)))

			#expect(store.state.prState == state)
			#expect(store.state.prUnresolvedDiscussions == nil)
		}
	}

	@Test("no PR clears all fields")
	@MainActor
	func missingPullRequestClearsState() async {
		var row = makeRow()
		row.prUrl = "https://gitlab.com/g/app/-/merge_requests/7"
		row.prState = .ready
		row.prProvider = .gitlab
		row.pipelineState = .running
		row.pipelineUrl = "https://gitlab.com/g/app/-/pipelines/42"
		row.prUnresolvedDiscussions = 3
		row.prApprovals = ApprovalStatus(decision: .approved, approvedBy: [Self.astrid])
		let store = makeStore(state: row)

		await store.send(.didFetchPullRequest(nil))

		#expect(store.state.prUrl == nil)
		#expect(store.state.prState == nil)
		#expect(store.state.prProvider == nil)
		#expect(store.state.pipelineState == nil)
		#expect(store.state.pipelineUrl == nil)
		#expect(store.state.prUnresolvedDiscussions == nil)
		#expect(store.state.prApprovals == nil)
		#expect(store.state.approvalSlot == nil)
	}

	private func makePopulatedRow() -> RepositoryRowReducer.State {
		var row = makeRow()
		row.prUrl = "https://gitlab.com/g/app/-/merge_requests/7"
		row.prState = .ready
		row.prProvider = .gitlab
		row.pipelineState = .running
		row.pipelineUrl = "https://gitlab.com/g/app/-/pipelines/42"
		row.prUnresolvedDiscussions = 3
		row.prApprovals = ApprovalStatus(decision: .approved, approvedBy: [Self.astrid])
		return row
	}

	@MainActor
	private func makeFailingFetchStore(
		state: RepositoryRowReducer.State,
		error: GitHostingError = .httpFailure(statusCode: 500)
	) -> TestStoreOf<RepositoryRowReducer> {
		let store = TestStore(initialState: state) {
			RepositoryRowReducer()
		} withDependencies: {
			$0[GitClient.self].getOriginRemote = { _ in GitRemote(host: "gitlab.com", owner: "g", repo: "app") }
			$0[PullRequestClient.self].fetchDetails = { _, _ in
				throw error
			}
		}
		store.exhaustivity = .off
		return store
	}

	@Test("a failed provider fetch on the same branch keeps the last-known PR state")
	@MainActor
	func failedFetchKeepsState() async {
		let store = makeFailingFetchStore(state: makePopulatedRow())

		await store.send(.didFetchStatus(GitPorcelainStatus(parsing: "# branch.head LS-1234_feature"), false))
		await store.finish()

		#expect(store.state.prUrl == "https://gitlab.com/g/app/-/merge_requests/7")
		#expect(store.state.prState == .ready)
		#expect(store.state.prProvider == .gitlab)
		#expect(store.state.pipelineState == .running)
		#expect(store.state.pipelineUrl == "https://gitlab.com/g/app/-/pipelines/42")
		#expect(store.state.prUnresolvedDiscussions == 3)
		#expect(store.state.prApprovals?.decision == .approved)
	}

	@Test("a branch switch clears PR state even when the provider fetch fails")
	@MainActor
	func branchSwitchClearsStateDespiteFailedFetch() async {
		let store = makeFailingFetchStore(state: makePopulatedRow())

		await store.send(.didFetchStatus(GitPorcelainStatus(parsing: "# branch.head LS-9999_other"), false))
		await store.finish()

		#expect(store.state.prUrl == nil)
		#expect(store.state.prState == nil)
		#expect(store.state.prProvider == nil)
		#expect(store.state.pipelineState == nil)
		#expect(store.state.pipelineUrl == nil)
		#expect(store.state.prUnresolvedDiscussions == nil)
		#expect(store.state.prApprovals == nil)
	}

	// MARK: - Fetch error surfacing

	@Test("a failed fetch surfaces a condensed provider-aware error message")
	@MainActor
	func failedFetchSetsErrorMessage() async {
		let store = makeFailingFetchStore(state: makeRow())

		await store.send(.didFetchStatus(GitPorcelainStatus(parsing: "# branch.head LS-1234_feature"), false))
		await store.receive(\.didFetchPullRequestFailed)

		#expect(store.state.prFetchError == "GitLab MR fetch failed: HTTP 500")
	}

	@Test("a 401 points the user at the token in Settings")
	@MainActor
	func unauthorizedFetchHintsAtSettings() async {
		let store = makeFailingFetchStore(state: makeRow(), error: .httpFailure(statusCode: 401))

		await store.send(.didFetchStatus(GitPorcelainStatus(parsing: "# branch.head LS-1234_feature"), false))
		await store.receive(\.didFetchPullRequestFailed)

		#expect(store.state.prFetchError == "GitLab MR fetch failed: HTTP 401 — check your token in Settings")
	}

	@Test("a token without project access surfaces a settings hint")
	@MainActor
	func inaccessibleProjectSetsErrorMessage() async {
		let store = makeFailingFetchStore(state: makeRow(), error: .unauthenticated)

		await store.send(.didFetchStatus(GitPorcelainStatus(parsing: "# branch.head LS-1234_feature"), false))
		await store.receive(\.didFetchPullRequestFailed)

		#expect(
			store.state.prFetchError ==
				"GitLab MR fetch failed: the token can't access this project — check its type and scope in Settings"
		)
	}

	@Test("a missing token stays silent — unconfigured integration is not an error")
	@MainActor
	func missingTokenShowsNoError() async {
		let store = makeFailingFetchStore(state: makeRow(), error: .missingToken)

		await store.send(.didFetchStatus(GitPorcelainStatus(parsing: "# branch.head LS-1234_feature"), false))
		await store.finish()
		// Apply anything the effects did send, so the nil below can't pass on a
		// buffered-but-unapplied failure action.
		await store.skipReceivedActions(strict: false)

		#expect(store.state.prFetchError == nil)
	}

	@Test("any completed fetch clears the error, including a confirmed no-PR answer")
	@MainActor
	func completedFetchClearsError() async {
		var row = makeRow()
		row.prFetchError = "GitLab MR fetch failed: HTTP 500"
		let store = makeStore(state: row)

		await store.send(.didFetchPullRequest(nil))

		#expect(store.state.prFetchError == nil)
	}

	@Test("a branch switch drops the previous branch's fetch error")
	@MainActor
	func branchSwitchClearsError() async {
		var row = makePopulatedRow()
		row.prFetchError = "GitLab MR fetch failed: HTTP 500"
		// The new branch's fetch is silent (missing token), so a surviving message
		// could only be the stale one.
		let store = makeFailingFetchStore(state: row, error: .missingToken)

		await store.send(.didFetchStatus(GitPorcelainStatus(parsing: "# branch.head LS-9999_other"), false))
		await store.finish()
		await store.skipReceivedActions(strict: false)

		#expect(store.state.prFetchError == nil)
	}

	// MARK: - Approvals

	private static let astrid = Reviewer(
		username: "aberg",
		displayName: "Astrid Berg",
		avatarURL: "https://gitlab.com/uploads/a.png"
	)
	private static let rohan = Reviewer(username: "rmehta", displayName: "Rohan Mehta")

	@MainActor
	private func sendPullRequest(
		state: PullRequestState,
		approvals: ApprovalStatus?,
		to store: TestStoreOf<RepositoryRowReducer>
	) async {
		await store.send(.didFetchPullRequest(PullRequestDetails(
			url: "https://gitlab.com/g/app/-/merge_requests/7",
			state: state,
			provider: .gitlab,
			approvals: approvals
		)))
	}

	@Test("an open PR keeps its approval status and shows it in the slot")
	@MainActor
	func openPullRequestKeepsApprovals() async {
		let store = makeStore(state: makeRow())
		let approvals = ApprovalStatus(
			decision: .approved,
			approvedBy: [Self.astrid],
			approvalsRequired: 2
		)

		await sendPullRequest(state: .ready, approvals: approvals, to: store)

		#expect(store.state.prApprovals == approvals)
		#expect(store.state.approvalSlot == .review(approvals))
	}

	@Test("a blocked PR carries its blockers through to the slot")
	@MainActor
	func changesRequestedCarriesBlockers() async {
		let store = makeStore(state: makeRow())
		let approvals = ApprovalStatus(
			decision: .changesRequested,
			approvedBy: [Self.astrid],
			changesRequestedBy: [Self.rohan]
		)

		await sendPullRequest(state: .ready, approvals: approvals, to: store)

		#expect(store.state.approvalSlot == .review(approvals))
		#expect(store.state.prApprovals?.changesRequestedBy == [Self.rohan])
	}

	@Test("a draft PR shows draft status instead of its review state")
	@MainActor
	func draftPullRequestShowsDraftSlot() async {
		let store = makeStore(state: makeRow())
		// Deliberately approved: draft still wins, because nobody is expected to be
		// reviewing a draft and a review verdict there would misread.
		let approvals = ApprovalStatus(decision: .approved, approvedBy: [Self.astrid])

		await sendPullRequest(state: .draft, approvals: approvals, to: store)

		#expect(store.state.prApprovals == approvals)
		#expect(store.state.approvalSlot == .draft)
	}

	@Test("merged and closed PRs drop approvals and show no slot")
	@MainActor
	func mergedAndClosedHideApprovals() async {
		for state in [PullRequestState.merged, .closed] {
			var row = makeRow()
			row.prApprovals = ApprovalStatus(decision: .approved, approvedBy: [Self.astrid])
			let store = makeStore(state: row)

			await sendPullRequest(
				state: state,
				approvals: ApprovalStatus(decision: .approved, approvedBy: [Self.astrid]),
				to: store
			)

			#expect(store.state.prApprovals == nil)
			#expect(store.state.approvalSlot == nil)
		}
	}

	@Test("an open PR whose provider reported no approvals shows no slot")
	@MainActor
	func missingApprovalsShowNoSlot() async {
		let store = makeStore(state: makeRow())

		await sendPullRequest(state: .ready, approvals: nil, to: store)

		// Nil means "not answered", not "nobody approved" — the provider always
		// reports a decision for a visible PR, so drawing a gray icon here would be
		// inventing a verdict the fetch never gave.
		#expect(store.state.prApprovals == nil)
		#expect(store.state.approvalSlot == nil)
	}

	@Test("no slot before any PR fetch has answered")
	@MainActor
	func noSlotBeforeFetch() {
		#expect(makeRow().approvalSlot == nil)
	}
}
