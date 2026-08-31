import ComposableArchitecture
import Foundation
import AppUI
import ToolsIntegration

// MARK: - YouTrack Button Reducer

/// Drives the per-row YouTrack menu. Its transition list is whatever the state machine reports
/// as reachable from the ticket's current state, so the menu never offers a move YouTrack would
/// reject — see ``YouTrackService/parseIssueDetails(from:)``.
@Reducer
public struct YouTrackButtonReducer: Sendable {
	@ObservableState
	public struct State: Equatable {
		public let ticketId: String
		/// Base URL of the YouTrack instance the ticket lives on, from the repo group's settings.
		public let baseURL: String
		/// The issue's State field, needed to address the write. Per-project, so it comes from
		/// the fetch rather than a constant.
		public let stateFieldId: String
		public var currentState: TicketState?
		public var transitions: [TicketStateTransition]
		public var isApplying = false
		@Presents
		public var alert: ScrollableAlertReducer.State?

		public init(
			ticketId: String,
			baseURL: String,
			stateFieldId: String,
			currentState: TicketState?,
			transitions: [TicketStateTransition]
		) {
			self.ticketId = ticketId
			self.baseURL = baseURL
			self.stateFieldId = stateFieldId
			self.currentState = currentState
			self.transitions = transitions
		}
	}

	public enum Action {
		case transitionTapped(TicketStateTransition)
		case transitionCompleted(TicketStateTransition, Result<Void, Error>)
		case alert(PresentationAction<ScrollableAlertReducer.Action>)
		case delegate(Delegate)

		@CasePathable
		public enum Delegate: Equatable {
			/// The ticket moved. The parent re-fetches so both the state chip and the now-stale
			/// transition list reflect the new state.
			case stateChanged
		}
	}

	@Dependency(YouTrackClient.self)
	private var youTrackClient

	public init() {}

	public var body: some Reducer<State, Action> {
		Reduce { state, action in
			switch action {
			case let .transitionTapped(transition):
				guard !state.isApplying else {
					return .none
				}

				state.isApplying = true

				@Shared(.youtrackAuthToken)
				var authToken = ""

				return .run { [
					ticketId = state.ticketId,
					fieldId = state.stateFieldId,
					baseURL = state.baseURL,
					transition,
					authToken
				] send in
					do {
						try await youTrackClient.applyStateEvent(
							ticketId,
							fieldId,
							transition.eventId,
							baseURL,
							authToken
						)
						await send(.transitionCompleted(transition, .success(())))
					}
					catch {
						await send(.transitionCompleted(transition, .failure(error)))
					}
				}

			case let .transitionCompleted(transition, result):
				state.isApplying = false
				switch result {
				case .success:
					return .send(.delegate(.stateChanged))

				case let .failure(error):
					state.alert = .init(
						title: "Move to \(transition.presentation) Failed",
						message: error.localizedDescription,
						isError: true
					)
					return .none
				}

			case .alert, .delegate:
				return .none
			}
		}
		.ifLet(\.$alert, action: \.alert) {
			ScrollableAlertReducer()
		}
	}
}
