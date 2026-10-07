import AppKit
import SwiftUI

extension View {
	/// Makes the view's empty space act as the window's title bar: a double-click does what
	/// System Settings ▸ Desktop & Dock says a title bar double-click does (zoom by default), and
	/// a drag moves the window.
	///
	/// The main window uses `.hiddenTitleBar`, so the app's own header sits where the title bar
	/// would be, and AppKit treats it as ordinary content: double-clicking it did nothing. Controls
	/// inside the view keep their clicks; only what falls through to the background is handled.
	/// Apply it before any `.background(Color…)`: a color in front of it takes the clicks.
	///
	/// SwiftUI gestures, not an `NSView` overriding `mouseDown`: the hosting view routes clicks
	/// itself and reached a background `NSView` only over part of the header.
	public func windowTitleBarArea() -> some View {
		background {
			Color.clear
				.contentShape(Rectangle())
				.onTapGesture(count: 2) {
					// The event being handled is the double-click itself, so it names the window.
					guard let window = NSApp.currentEvent?.window ?? NSApp.keyWindow else {
						return
					}

					TitleBarDoubleClickAction.current.perform(on: window)
				}
				// The tap gesture claims the click, which stops the hosting view moving the
				// window from here on its own.
				.gesture(WindowDragGesture())
				// Also covers the strip the hidden title bar leaves above the view.
				.ignoresSafeArea(edges: .top)
		}
	}
}

/// The user's choice for a title bar double-click, as AppKit's own title bar reads it.
private enum TitleBarDoubleClickAction {
	case zoom
	case minimize
	case none

	static var current: Self {
		let defaults = UserDefaults.standard
		switch defaults.string(forKey: "AppleActionOnDoubleClick") {
		case "Minimize":
			return .minimize
		case "None":
			return .none
		// "Maximize" (shown as Zoom) and "Fill": zooming a window with no maximum size fills
		// the screen's visible area.
		case .some:
			return .zoom
		case nil:
			// Set only by systems older than the setting above, which offered minimize or nothing.
			return defaults.bool(forKey: "AppleMiniaturizeOnDoubleClick") ? .minimize : .zoom
		}
	}

	@MainActor
	func perform(on window: NSWindow) {
		switch self {
		case .zoom:
			window.performZoom(nil)
		case .minimize:
			window.performMiniaturize(nil)
		case .none:
			break
		}
	}
}
