import ComposableArchitecture
import Foundation
import GitCore
import Testing
import ToolsIntegration
import YouTrackMenu
@testable import RepositoryFeature

@Suite("Repository row YouTrack menu wiring")
struct RepositoryRowYouTrackButtonTests {
	private let transitions = [
		TicketStateTransition(eventId: "take", presentation: "In Progress"),
		TicketStateTransition(eventId: "done", presentation: "Done"),
	]

	private func makeRow() -> RepositoryRowReducer.State {
		RepositoryRowReducer.State(
			path: "/repos/app",
			name: "app",
			branchName: "MOB-4432_feature",
			ticketIdRegex: "[A-Z]+-\\d+",
			youtrackBaseURL: "https://youtrack.example.com"
		)
	}

	private func makeDetails(
		stateFieldId: String? = "84-950",
		transitions: [TicketStateTransition]
	) -> IssueDetails {
		IssueDetails(
			androidCR: nil,
			iosCR: nil,
			androidReviewerName: nil,
			iosReviewerName: nil,
			ticketState: .open,
			stateFieldId: stateFieldId,
			stateTransitions: transitions
		)
	}

	@Test("reachable transitions populate the menu for the row's ticket")
	@MainActor
	func populatesMenu() async {
		let store = TestStore(initialState: makeRow()) {
			RepositoryRowReducer()
		}
		store.exhaustivity = .off

		await store.send(.didFetchYouTrack(makeDetails(transitions: transitions)))

		#expect(store.state.youtrackButton?.ticketId == "MOB-4432")
		#expect(store.state.youtrackButton?.stateFieldId == "84-950")
		#expect(store.state.youtrackButton?.currentState == .open)
		#expect(store.state.youtrackButton?.transitions == transitions)
	}

	@Test("no reachable transitions hides the menu", arguments: [true, false])
	@MainActor
	func hidesMenuWithoutTransitions(hasFieldId: Bool) async {
		let store = TestStore(initialState: makeRow()) {
			RepositoryRowReducer()
		}
		store.exhaustivity = .off

		await store.send(.didFetchYouTrack(makeDetails(
			stateFieldId: hasFieldId ? "84-950" : nil,
			transitions: hasFieldId ? [] : transitions
		)))

		#expect(store.state.youtrackButton == nil)
	}

	@Test("a failed YouTrack fetch hides the menu rather than offering stale transitions")
	@MainActor
	func failedFetchHidesMenu() async {
		var state = makeRow()
		state.youtrackButton = .init(
			ticketId: "MOB-4432",
			baseURL: "https://youtrack.example.com",
			stateFieldId: "84-950",
			currentState: .open,
			transitions: transitions
		)
		let store = TestStore(initialState: state) {
			RepositoryRowReducer()
		}
		store.exhaustivity = .off

		await store.send(.didFetchYouTrack(nil))

		#expect(store.state.youtrackButton == nil)
	}

	@Test("switching to a branch without a ticket clears the menu")
	@MainActor
	func clearsMenuOnTicketChange() async {
		var state = makeRow()
		state.youtrackButton = .init(
			ticketId: "MOB-4432",
			baseURL: "https://youtrack.example.com",
			stateFieldId: "84-950",
			currentState: .open,
			transitions: transitions
		)
		let store = TestStore(initialState: state) {
			RepositoryRowReducer()
		}
		store.exhaustivity = .off

		await store.send(.didFetchStatus(GitPorcelainStatus(parsing: "# branch.head master"), false))
		await store.finish()

		#expect(store.state.ticketId == nil)
		#expect(store.state.youtrackButton == nil)
	}

	@Test("a refresh landing mid-transition keeps the in-flight state")
	@MainActor
	func refreshPreservesInFlightState() async {
		var state = makeRow()
		var button = YouTrackButtonReducer.State(
			ticketId: "MOB-4432",
			baseURL: "https://youtrack.example.com",
			stateFieldId: "84-950",
			currentState: .open,
			transitions: transitions
		)
		button.isApplying = true
		state.youtrackButton = button

		let store = TestStore(initialState: state) {
			RepositoryRowReducer()
		}
		store.exhaustivity = .off

		await store.send(.didFetchYouTrack(makeDetails(transitions: transitions)))

		// Otherwise the progress indicator vanishes and a second transition becomes tappable.
		#expect(store.state.youtrackButton?.isApplying == true)
	}

	@Test("a completed state change re-reads the ticket")
	@MainActor
	func refetchesAfterStateChange() async {
		var state = makeRow()
		state.youtrackButton = .init(
			ticketId: "MOB-4432",
			baseURL: "https://youtrack.example.com",
			stateFieldId: "84-950",
			currentState: .open,
			transitions: transitions
		)
		let updated = makeDetails(transitions: [
			TicketStateTransition(eventId: "reopen", presentation: "Open"),
		])

		let store = TestStore(initialState: state) {
			RepositoryRowReducer()
		} withDependencies: {
			$0[YouTrackClient.self].fetchIssueDetails = { _, _, _ in updated }
		}
		store.exhaustivity = .off

		await store.send(.youtrackButton(.delegate(.stateChanged)))
		await store.receive(\.didFetchYouTrack)
		await store.finish()

		// The menu now reflects the transitions reachable from the new state.
		#expect(store.state.youtrackButton?.transitions == updated.stateTransitions)
	}
}
