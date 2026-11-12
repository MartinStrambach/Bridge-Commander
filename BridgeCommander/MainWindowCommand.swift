import AppKit
import SwiftUI

/// The main window while it is open. Each main window builds its own stores, scan and terminal
/// panes, and they write the same files, so there must never be two (see README).
@MainActor
final class MainWindowTracker {
	static let shared = MainWindowTracker()

	/// A closed window can stay alive for a while after it closes, so one still referenced here
	/// counts only while it is on screen or in the Dock.
	var window: NSWindow? {
		guard let recordedWindow, recordedWindow.isVisible || recordedWindow.isMiniaturized else {
			return nil
		}

		return recordedWindow
	}

	fileprivate weak var recordedWindow: NSWindow?
}

extension View {
	/// Marks the window holding this view as the app's main window.
	func tracksMainWindow() -> some View {
		background(MainWindowReader())
	}
}

/// File ▸ New Window (⌘N): opens the main window when it is closed — as a Dock click does —
/// and otherwise brings the open one forward instead of a second. Replaces the WindowGroup's
/// own item rather than removing it: with nothing of SwiftUI's own left in it, SwiftUI drops the
/// whole File menu, Close (⌘W) included.
struct NewMainWindowCommand: View {
	@Environment(\.openWindow)
	private var openWindow

	var body: some View {
		Button("New Window") {
			guard let window = MainWindowTracker.shared.window else {
				openWindow(id: "main")
				return
			}

			if window.isMiniaturized {
				window.deminiaturize(nil)
			}
			window.makeKeyAndOrderFront(nil)
			NSApp.activate()
		}
		.keyboardShortcut("n")
	}
}

private struct MainWindowReader: NSViewRepresentable {
	func makeNSView(context: Context) -> NSView {
		WindowReportingView(frame: .zero)
	}

	func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class WindowReportingView: NSView {
	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		if let window {
			MainWindowTracker.shared.recordedWindow = window
		}
	}
}
