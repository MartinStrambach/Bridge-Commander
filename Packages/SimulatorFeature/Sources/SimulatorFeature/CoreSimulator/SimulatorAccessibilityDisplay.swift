import CoreGraphics
import Foundation

/// The screen the accessibility calls address, and how the frames they return reach the
/// interface's space.
///
/// On the main screen, frames come back in the interface's space and hit-testing takes the point
/// on the portrait panel. An open iPhone Duo's inner panel (screen 3) needs its ID: with 0 the
/// tree read is still the inner panel's, but hit-testing finds nothing anywhere. There, apps'
/// frames are in the interface's space too, but SpringBoard's — the home screen's — come back in
/// the panel's native portrait space, and the application element's own frame is the panel's or
/// even the cover's size whatever is shown (checked live, 2026-10-08).
struct SimulatorAccessibilityDisplay: Equatable, Sendable {
	struct Panel: Equatable, Sendable {
		var rotation: SimulatorScreenRotation
		/// In points.
		var nativeSize: CGSize
	}

	/// `displayId` of the translator's calls: 0 for the main screen, else the screen's ID.
	var id: UInt32
	/// The panel when it is not the main screen; nil leaves frames as they come.
	var panel: Panel?

	static let main = SimulatorAccessibilityDisplay(id: 0, panel: nil)

	/// A frontmost application's tree with its frames in the interface's space, the application's
	/// own the whole screen.
	func interfaceTree(_ tree: SimulatorAccessibilityNode, isSpringBoard: Bool) -> SimulatorAccessibilityNode {
		guard let panel else {
			return tree
		}
		var mapped = interfaceFrames(tree, isSpringBoard: isSpringBoard)
		mapped.frame = CGRect(origin: .zero, size: panel.rotation.displayedSize(native: panel.nativeSize))
		return mapped
	}

	/// An element and its descendants with their frames in the interface's space.
	func interfaceFrames(_ node: SimulatorAccessibilityNode, isSpringBoard: Bool) -> SimulatorAccessibilityNode {
		guard panel != nil, isSpringBoard else {
			return node
		}
		var mapped = node
		mapped.frame = interfaceRect(node.frame, isSpringBoard: true)
		mapped.children = node.children.map { interfaceFrames($0, isSpringBoard: true) }
		return mapped
	}

	func interfaceRect(_ rect: CGRect, isSpringBoard: Bool) -> CGRect {
		guard let panel, isSpringBoard else {
			return rect
		}
		return panel.rotation.displayedRect(fromNative: rect, nativeSize: panel.nativeSize)
	}
}
