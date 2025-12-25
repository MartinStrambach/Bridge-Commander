import ComposableArchitecture
import SwiftUI

struct ShareButtonView: View {
	let store: StoreOf<ShareButtonReducer>

	var body: some View {
		ShareLink(item: store.shareText) {
			Image(systemName: "square.and.arrow.up")
				.resizable()
				.scaledToFit()
				.frame(width: 20, height: 20)
		}
		.foregroundColor(.secondary)
		.help("Share branch, ticket, and PR")
	}
}

#Preview {
	ShareButtonView(
		store: Store(
			initialState: ShareButtonReducer.State(
				branchName: "MOB-1234-feature-name",
				ticketURL: "https://youtrack.livesport.eu/issue/MOB-1234",
			),
			reducer: {
				ShareButtonReducer()
			}
		)
	)
}
