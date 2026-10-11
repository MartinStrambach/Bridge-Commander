import AppKit
import SwiftUI

public extension View {
	/// Shows something AppKit draws relative to this view — a menu, a share picker — while `item`
	/// is set, and clears `item` once it is gone.
	///
	/// An anchor `NSView` sits behind this view only meanwhile, so a view that offers such a thing
	/// costs nothing extra until it is used: the repository list builds a row each time it scrolls
	/// into view. `present` gets the item, the anchor (whose bounds are this view's frame) and a
	/// closure to call when the presentation has ended. It runs after the SwiftUI update that
	/// added the anchor, so it may run a tracking loop (`NSMenu.popUp`).
	func appKitPresentation<Item>(
		item: Binding<Item?>,
		present: @escaping @MainActor (Item, NSView, _ ended: @escaping @MainActor () -> Void) -> Void
	) -> some View {
		background {
			if let value = item.wrappedValue {
				AppKitPresentationAnchor { view, ended in
					present(value, view, ended)
				} onEnd: {
					item.wrappedValue = nil
				}
			}
		}
	}

	/// `.help(text)`, left off when there is no text. An empty tooltip is not shown, but still
	/// costs each view a tooltip modifier.
	@ViewBuilder
	func help(unlessEmpty text: String?) -> some View {
		if let text, !text.isEmpty {
			help(text)
		}
		else {
			self
		}
	}
}

private struct AppKitPresentationAnchor: NSViewRepresentable {
	let present: @MainActor (NSView, _ ended: @escaping @MainActor () -> Void) -> Void
	let onEnd: @MainActor () -> Void

	func makeNSView(context: Context) -> AnchorView {
		AnchorView()
	}

	func updateNSView(_ view: AnchorView, context: Context) {
		view.presentOnce(present, onEnd: onEnd)
	}

	final class AnchorView: NSView {
		private var hasPresented = false

		/// Each anchor presents once: it is created when the item is set and removed when the
		/// presentation ends.
		func presentOnce(
			_ present: @escaping @MainActor (NSView, _ ended: @escaping @MainActor () -> Void) -> Void,
			onEnd: @escaping @MainActor () -> Void
		) {
			guard !hasPresented else {
				return
			}

			hasPresented = true
			// After the SwiftUI update that added this view, once it has a frame.
			Task { @MainActor [weak self] in
				guard let self, window != nil else {
					onEnd()
					return
				}

				present(self, onEnd)
			}
		}
	}
}
