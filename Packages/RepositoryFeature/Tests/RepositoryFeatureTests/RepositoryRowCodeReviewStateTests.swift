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
}
