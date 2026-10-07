import ComposableArchitecture
import SwiftUI

struct ShareButtonView: View {
	let store: StoreOf<ShareButtonReducer>

	enum Style { case button, menuItem }

	var style: Style = .button

	var body: some View {
		switch style {
		case .button:
			ShareLink(item: store.shareText) {
				Image(systemName: "square.and.arrow.up")
					.resizable()
					.scaledToFit()
					.frame(width: 20, height: 20)
			}
			.foregroundColor(.secondary)
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
