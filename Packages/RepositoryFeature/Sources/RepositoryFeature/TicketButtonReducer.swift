import AppKit
import ComposableArchitecture
import Foundation
import ToolsIntegration

@Reducer
struct TicketButtonReducer {
	@ObservableState
	struct State: Equatable {
		let ticketId: String
		/// Resolved browser URL of the ticket on the group's YouTrack instance. The state is only
		/// constructed when a base URL is configured, so this is always non-empty.
		let ticketURL: String
	}

	enum Action: Equatable {
		case openTicketButtonTapped
	}

	var body: some Reducer<State, Action> {
		Reduce { state, action in
			switch action {
			case .openTicketButtonTapped:
				.run { [ticketURL = state.ticketURL] _ in
					guard let url = URL(string: ticketURL) else {
						return
					}
					_ = await MainActor.run {
						NSWorkspace.shared.open(url)
					}
				}
			}
		}
	}
}
