import ComposableArchitecture
import SwiftUI
import AppUI

// MARK: - Ticket Button View

struct TicketButtonView: View {
	let store: StoreOf<TicketButtonReducer>

	var body: some View {
		// The YouTrack mark rather than a generic ticket symbol: this button only exists once a
		// YouTrack base URL is configured for the row (the state is not built otherwise), so
		// wherever it shows, the destination really is YouTrack.
		//
		// The asset is deliberately not the full-color logo: `ActionButton` tints custom images as
		// templates, which would flatten the pink swoosh, the black square and the white letters
		// into one silhouette. It is the logo's square with the "YT" knocked out as holes, so the
		// mark survives being painted in a single tint like every other button in the row.
		ActionButton(
			icon: .customImage("youtrack"),
			tooltip: "Open YouTrack ticket \(store.ticketId)",
			action: { store.send(.openTicketButtonTapped) }
		)
	}
}

#Preview {
	TicketButtonView(
		store: Store(
			initialState: TicketButtonReducer.State(
				ticketId: "MOB-1234",
				ticketURL: "https://youtrack.example.com/issue/MOB-1234"
			),
			reducer: {
				TicketButtonReducer()
			}
		)
	)
}
