import ComposableArchitecture
import GitCore
import Testing
import ToolsIntegration
@testable import RepositoryFeature

@Suite("Repository row ticket button gating on the YouTrack base URL")
struct RepositoryRowTicketButtonGatingTests {
	private func makeRow(youtrackBaseURL: String) -> RepositoryRowReducer.State {
		RepositoryRowReducer.State(
			path: "/repos/app",
			name: "app",
			branchName: "MOB-4432_feature",
			ticketIdRegex: "[A-Z]+-\\d+",
			youtrackBaseURL: youtrackBaseURL
		)
	}

	@Test("without a base URL the ticket id still parses but the button and share line are gone")
	func emptyBaseURLKeepsTicketIdButHidesButton() {
		let state = makeRow(youtrackBaseURL: "")

		#expect(state.ticketId == "MOB-4432")
		#expect(state.ticketButton == nil)
		#expect(!state.shareButton.shareText.contains("Ticket:"))
	}

	@Test("a ticket without a base URL surfaces the missing-URL warning in the button's place")
	func emptyBaseURLShowsMissingURLWarning() {
		#expect(makeRow(youtrackBaseURL: "").showsMissingYouTrackURLWarning)
		// A slash-only value normalizes to empty and is just as unusable.
		#expect(makeRow(youtrackBaseURL: "/").showsMissingYouTrackURLWarning)
	}

	@Test("no warning without a ticket: a group that doesn't parse tickets isn't misconfigured")
	func noTicketMeansNoWarning() {
		let state = RepositoryRowReducer.State(
			path: "/repos/app",
			name: "app",
			branchName: "main"
		)

		#expect(state.ticketId == nil)
		#expect(!state.showsMissingYouTrackURLWarning)
	}

	@Test("a configured base URL resolves the ticket button's browser URL")
	func configuredBaseURLBuildsTicketURL() {
		let state = makeRow(youtrackBaseURL: "https://youtrack.example.com")

		#expect(state.ticketButton?.ticketId == "MOB-4432")
		#expect(state.ticketButton?.ticketURL == "https://youtrack.example.com/issue/MOB-4432")
		#expect(state.shareButton.shareText.contains("Ticket: https://youtrack.example.com/issue/MOB-4432"))
		#expect(!state.showsMissingYouTrackURLWarning)
	}

	@Test("a trailing slash on the base URL still produces a clean issue URL")
	func trailingSlashBaseURLIsNormalized() {
		let state = makeRow(youtrackBaseURL: "https://youtrack.example.com/")

		#expect(state.ticketButton?.ticketURL == "https://youtrack.example.com/issue/MOB-4432")
	}

	@Test("without a base URL a refresh reports nil YouTrack details instead of fetching")
	@MainActor
	func emptyBaseURLSkipsYouTrackFetch() async {
		let store = TestStore(initialState: makeRow(youtrackBaseURL: "")) {
			RepositoryRowReducer()
		} withDependencies: {
			// fetchIssueDetails is deliberately left unimplemented: reaching it would
			// fail the test, proving the fetch is skipped when no instance is configured.
			$0[GitClient.self].getOriginRemote = { _ in nil }
		}
		store.exhaustivity = .off

		await store.send(.didFetchStatus(GitPorcelainStatus(parsing: "# branch.head MOB-4432_feature"), false))
		await store.receive(\.didFetchYouTrack)
		await store.finish()

		#expect(store.state.ticketId == "MOB-4432")
		#expect(store.state.youtrackButton == nil)
	}
}
