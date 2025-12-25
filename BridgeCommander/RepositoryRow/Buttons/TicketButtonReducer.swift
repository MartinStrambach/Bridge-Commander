import AppKit
import ComposableArchitecture
import Foundation

@Reducer
struct TicketButtonReducer {
	@ObservableState
	struct State: Equatable {
		let ticketId: String
	}

	enum Action: Equatable {
		case openTicketButtonTapped
	}

	var body: some Reducer<State, Action> {
		Reduce { state, action in
			switch action {
			case .openTicketButtonTapped:
				.run { [ticketId = state.ticketId] _ in
					await openTicketURL(ticketId: ticketId)
				}
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
