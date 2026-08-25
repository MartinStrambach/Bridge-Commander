import ComposableArchitecture
import GitCore
import Testing
import ToolsIntegration
@testable import RepositoryFeature

@Suite("Repository row code review state")
struct RepositoryRowCodeReviewStateTests {
	private func makeTicketBranchRow() -> RepositoryRowReducer.State {
		var state = RepositoryRowReducer.State(
			path: "/repos/app",
			name: "app",
			branchName: "LS-1234_feature",
			ticketIdRegex: "[A-Z]+-\\d+"
		)
		state.androidCR = .waiting
		state.iosCR = .waiting
		state.androidReviewerName = "Alice"
		state.iosReviewerName = "Bob"
		state.ticketState = .waitingToCodeReview
		return state
	}

	@Test("switching to the default branch clears ticket and code review state")
	@MainActor
	func clearsCodeReviewStateOnDefaultBranch() async {
		let store = TestStore(initialState: makeTicketBranchRow()) {
			RepositoryRowReducer()
		}
		store.exhaustivity = .off

		await store.send(.didFetchStatus(GitPorcelainStatus(parsing: "# branch.head master"), false))
		await store.receive(\.didFetchYouTrack)
		await store.finish()

		#expect(store.state.ticketId == nil)
		#expect(store.state.androidCR == nil)
		#expect(store.state.iosCR == nil)
		#expect(store.state.androidReviewerName == nil)
		#expect(store.state.iosReviewerName == nil)
		#expect(store.state.ticketState == nil)
		#expect(store.state.prState == nil)
	}

	@MainActor
	private func makeFailingYouTrackStore(state: RepositoryRowReducer.State) -> TestStoreOf<RepositoryRowReducer> {
		let store = TestStore(initialState: state) {
			RepositoryRowReducer()
		} withDependencies: {
			$0[YouTrackClient.self].fetchIssueDetails = { _, _ in
				throw YouTrackServiceError.httpFailure(statusCode: 500)
			}
			$0[GitClient.self].getOriginRemote = { _ in nil }
		}
		store.exhaustivity = .off
		return store
	}

	@Test("a failed YouTrack fetch on the same ticket keeps the last-known code review state")
	@MainActor
	func failedFetchKeepsCodeReviewState() async {
		let store = makeFailingYouTrackStore(state: makeTicketBranchRow())

		await store.send(.didFetchStatus(GitPorcelainStatus(parsing: "# branch.head LS-1234_feature"), false))
		await store.finish()

		#expect(store.state.androidCR == .waiting)
		#expect(store.state.iosCR == .waiting)
		#expect(store.state.androidReviewerName == "Alice")
		#expect(store.state.iosReviewerName == "Bob")
		#expect(store.state.ticketState == .waitingToCodeReview)
	}

	@Test("a ticket change clears code review state even when the YouTrack fetch fails")
	@MainActor
	func ticketChangeClearsStateDespiteFailedFetch() async {
		let store = makeFailingYouTrackStore(state: makeTicketBranchRow())

		await store.send(.didFetchStatus(GitPorcelainStatus(parsing: "# branch.head LS-9999_other"), false))
		await store.finish()

		#expect(store.state.ticketId == "LS-9999")
		#expect(store.state.androidCR == nil)
		#expect(store.state.iosCR == nil)
		#expect(store.state.androidReviewerName == nil)
		#expect(store.state.iosReviewerName == nil)
		#expect(store.state.ticketState == nil)
	}
}
