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
		let store = makeStore(state: row)

		await store.send(.didFetchPullRequest(nil))

		#expect(store.state.prUrl == nil)
		#expect(store.state.prState == nil)
		#expect(store.state.prProvider == nil)
		#expect(store.state.pipelineState == nil)
		#expect(store.state.pipelineUrl == nil)
		#expect(store.state.prUnresolvedDiscussions == nil)
	}

	private func makePopulatedRow() -> RepositoryRowReducer.State {
		var row = makeRow()
		row.prUrl = "https://gitlab.com/g/app/-/merge_requests/7"
		row.prState = .ready
		row.prProvider = .gitlab
		row.pipelineState = .running
		row.pipelineUrl = "https://gitlab.com/g/app/-/pipelines/42"
		row.prUnresolvedDiscussions = 3
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
}
