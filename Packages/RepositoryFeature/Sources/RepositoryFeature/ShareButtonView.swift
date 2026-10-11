import AppKit
import AppUI
import ComposableArchitecture
import SwiftUI

struct ShareButtonView: View {
	let store: StoreOf<ShareButtonReducer>

	/// The text being shared while the share picker is open.
	@State
	private var sharedText: String?

	var body: some View {
		// Not a `ShareLink`: that is a pop-up button built along with the row, and the list
		// rebuilds a row each time it scrolls into view. The picker is made only when pressed.
		Button {
			sharedText = store.shareText
		} label: {
			Image(systemName: "square.and.arrow.up")
				.resizable()
				.scaledToFit()
				.frame(width: 20, height: 20)
		}
		.foregroundColor(.secondary)
		.help("Share branch, ticket, and PR")
		.appKitPresentation(item: $sharedText) { text, anchor, ended in
			SharePicker.show(text, below: anchor, ended: ended)
		}
	}
}

/// The system share picker for some text, under a view, reporting when it closes.
@MainActor
private final class SharePicker: NSObject, @MainActor NSSharingServicePickerDelegate {
	private let ended: @MainActor () -> Void
	/// The picker holds its delegate weakly; this one lets go of itself once the picker closes.
	private var keptAlive: SharePicker?

	private init(ended: @escaping @MainActor () -> Void) {
		self.ended = ended
	}

	static func show(_ text: String, below view: NSView, ended: @escaping @MainActor () -> Void) {
		let delegate = SharePicker(ended: ended)
		delegate.keptAlive = delegate
		let picker = NSSharingServicePicker(items: [text])
		picker.delegate = delegate
		picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
	}

	/// Called with a service when one is chosen and with `nil` when the picker is dismissed.
	func sharingServicePicker(_ picker: NSSharingServicePicker, didChoose service: NSSharingService?) {
		ended()
		keptAlive = nil
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
