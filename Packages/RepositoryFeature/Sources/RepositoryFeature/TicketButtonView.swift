import ComposableArchitecture
import SwiftUI
import AppUI

// MARK: - Ticket Button View

struct TicketButtonView: View {
	let store: StoreOf<TicketButtonReducer>

	var body: some View {
		ActionButton(
			icon: .systemImage("ticket"),
			tooltip: "Open YouTrack ticket \(store.ticketId)",
			action: { store.send(.openTicketButtonTapped) }
		)
	}
}

#Preview {
	TicketButtonView(
		store: Store(
			initialState: TicketButtonReducer.State(
				ticketId: "MOB-1234"
			),
			reducer: {
				TicketButtonReducer()
			}
		)
	)
}
