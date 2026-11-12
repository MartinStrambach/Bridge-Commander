import AppKit
import SwiftUI

public extension View {
	/// Shows something AppKit draws relative to this view — a menu, a share picker — while
	/// `isPresented` is true, and sets it back to false once it is gone.
	///
	/// An anchor `NSView` sits behind this view only meanwhile, so a view that offers such a thing
	/// costs nothing extra until it is used: the repository list builds a row each time it scrolls
	/// into view. `present` gets the anchor (whose bounds are this view's frame) and a closure to
	/// call when the presentation has ended. It runs after the SwiftUI update that added the
	/// anchor, so it may run a tracking loop (`NSMenu.popUp`).
	func appKitPresentation(
		isPresented: Binding<Bool>,
		present: @escaping @MainActor (NSView, _ ended: @escaping @MainActor () -> Void) -> Void
	) -> some View {
		background {
			if isPresented.wrappedValue {
				AppKitPresentationAnchor(present: present) {
					isPresented.wrappedValue = false
				}
			}
		}
	}
}

/// Presents once, when it is made: it is added when the presentation starts and removed when
/// it ends.
private struct AppKitPresentationAnchor: NSViewRepresentable {
	let present: @MainActor (NSView, _ ended: @escaping @MainActor () -> Void) -> Void
	let onEnd: @MainActor () -> Void

	func makeNSView(context: Context) -> NSView {
		let view = NSView()
		// After the SwiftUI update that added the view, once it has a frame.
		Task { @MainActor [weak view, present, onEnd] in
			guard let view, view.window != nil else {
				onEnd()
				return
			}

			present(view, onEnd)
		}
		return view
	}

	func updateNSView(_ view: NSView, context: Context) {}
}
