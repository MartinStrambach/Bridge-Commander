import ComposableArchitecture
import SwiftUI

// MARK: - Ticket Button View

struct TicketButtonView: View {
	let store: StoreOf<TicketButtonReducer>
	@EnvironmentObject
	var abbreviationMode: AbbreviationMode

	var body: some View {
		ToolButton(
			label: store.isOpening
				? (abbreviationMode.isAbbreviated ? "Open" : "Opening")
				: (abbreviationMode.isAbbreviated ? "Tkt" : "Ticket"),
			icon: .systemImage("ticket"),
			tooltip: store.isOpening ? "Opening ticket..." : "Open YouTrack ticket \(store.ticketId)",
			isProcessing: store.isOpening,
			tint: store.isOpening ? .orange : nil,
			action: { store.send(.openTicketButtonTapped) }
		)
		.environmentObject(abbreviationMode)
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
	.environmentObject(AbbreviationMode())
}
