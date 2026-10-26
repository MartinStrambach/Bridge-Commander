import AppKit
import SwiftUI

extension View {
	/// Runs `action` when the mouse's back button (button 4, `buttonNumber` 3) is pressed
	/// anywhere in the view's window, as a browser goes back on it.
	///
	/// SwiftUI has no event for the extra mouse buttons, so a local event monitor watches for
	/// them while the view is in a window. A press in another window — a sheet, an alert, the
	/// app's other windows — is left alone, as is one while the view is hidden. Only one view
	/// with it should be on screen in a window at a time: the views that use it show in place
	/// of one another.
	public func onMouseBackButton(perform action: @escaping @MainActor () -> Void) -> some View {
		background(MouseBackButtonMonitor(action: action))
	}
}

private struct MouseBackButtonMonitor: NSViewRepresentable {
	let action: @MainActor () -> Void

	func makeNSView(context: Context) -> MonitorView {
		let view = MonitorView()
		view.action = action
		return view
	}

	func updateNSView(_ view: MonitorView, context: Context) {
		view.action = action
	}

	final class MonitorView: NSView {
		/// What AppKit numbers the back button: 0 is the left button, 1 the right, 2 the middle.
		private static let backButtonNumber = 3

		var action: (@MainActor () -> Void)?
		private var monitor: Any?

		override func viewDidMoveToWindow() {
			super.viewDidMoveToWindow()
			// Leaving the window (which a view does before it goes away) removes the monitor,
			// so `deinit`, which is not on the main actor, has nothing to clean up.
			if let monitor {
				NSEvent.removeMonitor(monitor)
				self.monitor = nil
			}
			guard window != nil else {
				return
			}

			monitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown) { [weak self] event in
				// Local monitors run on the main thread.
				let handled = MainActor.assumeIsolated { self?.handle(event) ?? false }
				return handled ? nil : event
			}
		}

		private func handle(_ event: NSEvent) -> Bool {
			guard event.buttonNumber == Self.backButtonNumber,
			      let window, event.window === window,
			      !isHiddenOrHasHiddenAncestor,
			      let action
			else {
				return false
			}

			action()
			return true
		}

		// Clicks pass through to the content the monitor sits behind.
		override func hitTest(_ point: NSPoint) -> NSView? {
			nil
		}
	}
}
