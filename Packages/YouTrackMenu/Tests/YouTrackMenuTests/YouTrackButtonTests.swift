import ComposableArchitecture
import Foundation
import Testing
import ToolsIntegration
@testable import YouTrackMenu

@Suite("YouTrack state transition button")
struct YouTrackButtonTests {
	private let toReview = TicketStateTransition(eventId: "to review", presentation: "Waiting to code review")
	private let done = TicketStateTransition(eventId: "done", presentation: "Done")

	private func makeState(isApplying: Bool = false) -> YouTrackButtonReducer.State {
		var state = YouTrackButtonReducer.State(
			ticketId: "MOB-4039",
			stateFieldId: "84-950",
			currentState: .inProgress,
			transitions: [toReview, done]
		)
		state.isApplying = isApplying
		return state
	}

	@Test("a transition sends the event id for the tapped state and reports the change")
	@MainActor
	func appliesTappedTransition() async {
		let recorded = LockIsolated<[String]>([])
		let store = TestStore(initialState: makeState()) {
			YouTrackButtonReducer()
		} withDependencies: {
			$0[YouTrackClient.self].applyStateEvent = { ticketId, fieldId, eventId, authToken in
				recorded.withValue { $0 = [ticketId, fieldId, eventId, authToken] }
			}
		}

		await store.send(.transitionTapped(toReview)) {
			$0.isApplying = true
		}
		await store.receive(\.transitionCompleted) {
			$0.isApplying = false
		}
		await store.receive(\.delegate.stateChanged)

		#expect(recorded.value.prefix(3) == ["MOB-4039", "84-950", "to review"])
	}

	@Test("a second tap is ignored while a transition is in flight")
	@MainActor
	func ignoresTapWhileApplying() async {
		let store = TestStore(initialState: makeState(isApplying: true)) {
			YouTrackButtonReducer()
		}

		await store.send(.transitionTapped(done))

		#expect(store.state.isApplying)
	}

	@Test("a rejected transition surfaces an alert and does not report a change")
	@MainActor
	func failureShowsAlert() async {
		let store = TestStore(initialState: makeState()) {
			YouTrackButtonReducer()
		} withDependencies: {
			$0[YouTrackClient.self].applyStateEvent = { _, _, _, _ in
				throw YouTrackServiceError.httpFailure(statusCode: 400)
			}
		}

		await store.send(.transitionTapped(done)) {
			$0.isApplying = true
		}
		await store.receive(\.transitionCompleted) {
			$0.isApplying = false
			$0.alert = .init(
				title: "Move to Done Failed",
				message: YouTrackServiceError.httpFailure(statusCode: 400).localizedDescription,
				isError: true
			)
		}
	}
}
