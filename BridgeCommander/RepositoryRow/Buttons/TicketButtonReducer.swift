import AppKit
import ComposableArchitecture
import Foundation

@Reducer
struct TicketButtonReducer {
	@ObservableState
	struct State: Equatable {
		let ticketId: String
		var isOpening: Bool = false
	}

	enum Action: Equatable {
		case openTicketButtonTapped
		case didOpenTicket
	}

	var body: some Reducer<State, Action> {
		Reduce { state, action in
			switch action {
			case .openTicketButtonTapped:
				state.isOpening = true
				return .run { [ticketId = state.ticketId] send in
					await openTicketURL(ticketId: ticketId)
					await send(.didOpenTicket)
				}

			case .didOpenTicket:
				state.isOpening = false
				return .none
			}
		}
	}

	private func openTicketURL(ticketId: String) async {
		let urlString = "https://youtrack.livesport.eu/issue/\(ticketId)"
		if let url = URL(string: urlString) {
			_ = await MainActor.run {
				NSWorkspace.shared.open(url)
			}
		}
	}
}
