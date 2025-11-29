import ComposableArchitecture
import SwiftUI

// MARK: - Ticket Button View

struct TicketButtonView: View {
	let store: StoreOf<TicketButtonReducer>
	@EnvironmentObject
	var abbreviationMode: AbbreviationMode

	var body: some View {
		Group {
			if store.isOpening {
				HStack(spacing: 8) {
					ProgressView()
					Text(buttonLabel)
						.font(.body)
				}
				.frame(minWidth: abbreviationMode.isAbbreviated ? 50 : 100)
				.buttonStyle(.borderedProminent)
				.tint(.orange)
			}
			else {
				Button(action: { store.send(.openTicketButtonTapped) }) {
					Label(buttonLabel, systemImage: buttonIcon)
						.frame(minWidth: abbreviationMode.isAbbreviated ? 50 : 100)
				}
				.buttonStyle(.bordered)
			}
		}
		.controlSize(.small)
		.fixedSize(horizontal: true, vertical: false)
		.disabled(store.isOpening)
		.help(buttonTooltip)
	}

	// MARK: - Computed Properties

	private var buttonLabel: String {
		if store.isOpening {
			abbreviationMode.isAbbreviated ? "Open" : "Opening"
		}
		else {
			abbreviationMode.isAbbreviated ? "Tkt" : "Ticket"
		}
	}

	private var buttonIcon: String {
		"ticket"
	}

	private var buttonTooltip: String {
		if store.isOpening {
			"Opening ticket..."
		}
		else {
			"Open YouTrack ticket \(store.ticketId)"
		}
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
