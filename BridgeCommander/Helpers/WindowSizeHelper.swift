// BridgeCommander/Helpers/WindowSizeHelper.swift
import AppKit
import SwiftUI

struct WindowMinSizeModifier: ViewModifier {
	let minWidth: CGFloat
	let minHeight: CGFloat

	func body(content: Content) -> some View {
		content.background(
			WindowMinSizeHelper(minWidth: minWidth, minHeight: minHeight)
		)
	}
}

extension View {
	func windowMinSize(width: CGFloat, height: CGFloat) -> some View {
		modifier(WindowMinSizeModifier(minWidth: width, minHeight: height))
	}
}

private struct WindowMinSizeHelper: NSViewRepresentable {
	let minWidth: CGFloat
	let minHeight: CGFloat

	func makeNSView(context: Context) -> NSView {
		NSView(frame: .zero)
	}

	func updateNSView(_ nsView: NSView, context: Context) {
		let size = NSSize(width: minWidth, height: minHeight)
		guard nsView.window?.minSize != size else {
			return
		}

		DispatchQueue.main.async {
			nsView.window?.minSize = size
		}
	}
}
