import AppKit
import Foundation

/// What `SimulatorAccessibility.perform(_:on:device:)` did. A press it could not make is handed
/// back for `SimulatorHost` to tap, since the tap goes through the input service, not the translator.
enum SimulatorElementActionResult: Sendable {
	case done(SimulatorElementOutcome)
	case needsTap(SimulatorAccessibilityNode)
}

extension SimulatorAccessibility {
	/// Finds the element `query` means in the frontmost app and acts on it.
	///
	/// The walk, the match and the action happen in one turn of the work queue, on the live
	/// `NSAccessibilityElement` the walk read — not re-found afterwards by position, which a screen
	/// that changed in between would point at something else.
	func perform(
		_ action: SimulatorElementAction,
		on query: SimulatorElementQuery,
		device: ObjectBox
	) async throws -> SimulatorElementActionResult {
		try await withFrontmostApplication(device: device) { application in
			var nodes: [SimulatorAccessibilityNode] = []
			var elements: [NSAccessibilityElement] = []
			Self.collect(application, depth: 0, nodes: &nodes, elements: &elements)

			let position = try query.match(in: nodes, preferring: action.preferredRoles)
			return try Self.act(action, on: elements[position], found: nodes[position])
		}
	}

	/// The tree in depth-first order, element by element, under the same caps as `frontmostTree`.
	private static func collect(
		_ element: NSAccessibilityElement,
		depth: Int,
		nodes: inout [SimulatorAccessibilityNode],
		elements: inout [NSAccessibilityElement]
	) {
		nodes.append(attributes(of: element))
		elements.append(element)
		guard depth < maximumDepth else {
			return
		}
		for child in element.accessibilityChildren() ?? [] {
			guard nodes.count < maximumNodes else {
				return
			}
			if let child = child as? NSAccessibilityElement {
				collect(child, depth: depth + 1, nodes: &nodes, elements: &elements)
			}
		}
	}

	/// On the work queue only.
	private static func act(
		_ action: SimulatorElementAction,
		on element: NSAccessibilityElement,
		found node: SimulatorAccessibilityNode
	) throws -> SimulatorElementActionResult {
		switch action {
		case .press:
			// iOS lists AXPress on nearly everything and the translator reports success even for
			// static text, so `true` means "delivered", not "something happened"; `false` or a
			// missing action is the only signal there is to fall back to a tap on.
			let actions = ObjCRuntime.object(element, "accessibilityActionNames") as? [String] ?? []
			guard actions.contains(NSAccessibility.Action.press.rawValue), element.accessibilityPerformPress() else {
				return .needsTap(node)
			}
			return .done(SimulatorElementOutcome(element: node, effect: .pressed))

		case let .setValue(value):
			guard isSettable(element, attribute: NSAccessibility.Attribute.value.rawValue) else {
				throw SimulatorElementError.notSettable(element: SimulatorAccessibilityFormatter.line(for: node))
			}
			element.setAccessibilityValue(value)
			// Read back after the guest has had a moment: a field may reformat or refuse the text.
			Thread.sleep(forTimeInterval: 0.2)
			let readBack = attributes(of: element).value
			return .done(SimulatorElementOutcome(element: node, effect: .valueSet(readBack: readBack)))

		case .scrollToVisible:
			guard ObjCRuntime.responds(element, to: "performScrollToVisible") else {
				throw SimulatorElementError.notScrollable(element: SimulatorAccessibilityFormatter.line(for: node))
			}
			ObjCRuntime.send(element, "performScrollToVisible")
			// The scroll animates; the frame is worth reporting only once it has settled.
			Thread.sleep(forTimeInterval: 0.4)
			return .done(SimulatorElementOutcome(element: node, effect: .scrolled(to: element.accessibilityFrame())))

		case .increment, .decrement:
			let name = action == .increment ? NSAccessibility.Action.increment : NSAccessibility.Action.decrement
			let actions = ObjCRuntime.object(element, "accessibilityActionNames") as? [String] ?? []
			guard actions.contains(name.rawValue) else {
				throw SimulatorElementError.notAdjustable(element: SimulatorAccessibilityFormatter.line(for: node))
			}
			_ = action == .increment ? element.accessibilityPerformIncrement() : element.accessibilityPerformDecrement()
			// As for a value: the guest updates the value a moment later.
			Thread.sleep(forTimeInterval: 0.15)
			return .done(SimulatorElementOutcome(element: node, effect: .valueSet(readBack: attributes(of: element).value)))
		}
	}

	/// `-accessibilityIsAttributeSettable:`, which Swift only offers through the deprecated
	/// informal protocol.
	private static func isSettable(_ element: NSAccessibilityElement, attribute: String) -> Bool {
		typealias Settable = @convention(c) (AnyObject, Selector, NSString) -> Bool
		guard ObjCRuntime.responds(element, to: "accessibilityIsAttributeSettable:") else {
			return false
		}
		return unsafeBitCast(ObjCRuntime.messageSendFunction, to: Settable.self)(
			element,
			sel_registerName("accessibilityIsAttributeSettable:"),
			attribute as NSString
		)
	}
}
