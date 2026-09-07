// BridgeCommander/Helpers/WindowSizeHelper.swift
import AppKit
import SwiftUI

public struct WindowMinSizeModifier: ViewModifier {
	public let minWidth: CGFloat
	public let minHeight: CGFloat

	public init(minWidth: CGFloat, minHeight: CGFloat) {
		self.minWidth = minWidth
		self.minHeight = minHeight
	}

	public func body(content: Content) -> some View {
		content.background(
			WindowMinSizeHelper(minWidth: minWidth, minHeight: minHeight)
		)
	}
}

public struct WindowResizableModifier: ViewModifier {
	public init() {}

	public func body(content: Content) -> some View {
		content.background(WindowResizableHelper())
	}
}

extension View {
	public func windowMinSize(width: CGFloat, height: CGFloat) -> some View {
		modifier(WindowMinSizeModifier(minWidth: width, minHeight: height))
	}

	/// Lets the user drag the edges of the hosting window.
	///
	/// AppKit opens sheet windows without `.resizable` in their style mask, so a sheet stays
	/// at whatever size SwiftUI picked when it opened no matter how flexible the content's
	/// frame is. Putting the bit back gives the sheet the usual drag-to-resize edges; the
	/// bounds still come from the content's `minWidth`/`maxWidth`, which SwiftUI forwards to
	/// the window as its content size limits.
	public func windowResizable() -> some View {
		modifier(WindowResizableModifier())
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

private struct WindowResizableHelper: NSViewRepresentable {
	func makeNSView(context: Context) -> ResizableWindowView {
		ResizableWindowView()
	}

	func updateNSView(_ nsView: ResizableWindowView, context: Context) {}
}

private final class ResizableWindowView: NSView {
	/// `updateNSView` is no use here: for a sheet it can run before the hosting view is in a
	/// window, and there is no later update to retry on. The mask is also re-applied one
	/// runloop hop later, because SwiftUI finishes configuring the sheet window after its
	/// content view is installed and would otherwise overwrite the bit.
	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		makeWindowResizable()
		DispatchQueue.main.async { [weak self] in
			self?.makeWindowResizable()
		}
	}

	private func makeWindowResizable() {
		guard let window, !window.styleMask.contains(.resizable) else {
			return
		}

		window.styleMask.insert(.resizable)
	}
}
