import AppUI
import ComposableArchitecture
import SwiftUI

struct ShareButtonView: View {
	let store: StoreOf<ShareButtonReducer>

	@State
	private var isSharing = false

	var body: some View {
		// Not a `ShareLink`: that is a pop-up button built along with the row, and the list
		// rebuilds a row each time it scrolls into view. The picker is made only when pressed.
		Button {
			isSharing = true
		} label: {
			Image(systemName: "square.and.arrow.up")
				.resizable()
				.scaledToFit()
				.frame(width: 20, height: 20)
		}
		.foregroundColor(.secondary)
		.help("Share branch, ticket, and PR")
		.appKitPresentation(isPresented: $isSharing) { anchor, ended in
			SharePicker.show(store.shareText, below: anchor, ended: ended)
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
