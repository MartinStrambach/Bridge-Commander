import AppUI
import ComposableArchitecture
import SwiftUI

struct ShareButtonView: View {
	let store: StoreOf<ShareButtonReducer>

	enum Style { case button, menuItem }

	var style: Style = .button

	var body: some View {
		switch style {
		case .button:
			// Drawn like an `ActionButton`, which a ShareLink cannot be.
			ShareLink(item: store.shareText) {
				Image(systemName: "square.and.arrow.up")
					.resizable()
					.scaledToFit()
					.padding(6)
					.frame(width: 28, height: 28)
			}
			.buttonStyle(.tile())
			.foregroundStyle(.secondary)
			.help("Share branch, ticket, and PR")

		case .menuItem:
			ShareLink(item: store.shareText) {
				Label("Share Branch, Ticket and PR", systemImage: "square.and.arrow.up")
			}
		}
	}
}

#Preview {
	ShareButtonView(
		store: Store(
			initialState: ShareButtonReducer.State(
				branchName: "MOB-1234-feature-name",
				ticketURL: "https://youtrack.example.com/issue/MOB-1234",
			),
			reducer: {
				ShareButtonReducer()
			}
		)
	)
}
