import CoreGraphics
import Foundation

/// The accessibility tree as compact text for a model: one element per line, indented by nesting,
/// with what identifies it and where it is.
///
/// Containers that carry nothing themselves (no label, value or identifier, and not a control) are
/// left out and their children moved up, so the text is the screen's content rather than its
/// view hierarchy — a typical screen goes from hundreds of raw elements to a few dozen lines.
public nonisolated enum SimulatorAccessibilityFormatter {
	/// Roles kept even without a label: an unlabelled button is still something to tap.
	static let controlRoles: Set<String> = [
		"Button", "CheckBox", "ComboBox", "Incrementor", "Link", "MenuButton", "PopUpButton",
		"RadioButton", "SearchField", "Slider", "Switch", "Tab", "TextArea", "TextField", "Toggle",
	]

	public static func describe(tree root: SimulatorAccessibilityNode) -> String {
		var lines: [String] = []
		var count = 0
		append(root, depth: 0, into: &lines, count: &count, isRoot: true)
		let header = "\(root.label.map { "\"\($0)\"" } ?? root.role), \(count) elements. "
			+ "frame=(x,y,width,height) in points; tap an element's centre to activate it, or its tap= point when it has one."
		return ([header] + lines).joined(separator: "\n")
	}

	public static func describe(element: SimulatorAccessibilityNode) -> String {
		var lines: [String] = []
		var count = 0
		append(element, depth: 0, into: &lines, count: &count, isRoot: true)
		return lines.joined(separator: "\n")
	}

	private static func append(
		_ node: SimulatorAccessibilityNode,
		depth: Int,
		into lines: inout [String],
		count: inout Int,
		isRoot: Bool
	) {
		let kept = isRoot || isInformative(node)
		if kept {
			lines.append(String(repeating: "  ", count: depth) + line(for: node))
			count += 1
		}
		for child in node.children {
			append(child, depth: kept ? depth + 1 : depth, into: &lines, count: &count, isRoot: false)
		}
	}

	static func isInformative(_ node: SimulatorAccessibilityNode) -> Bool {
		guard node.frame.width > 0, node.frame.height > 0 else {
			return false
		}
		return node.label != nil || node.value != nil || node.identifier != nil || controlRoles.contains(node.role)
	}

	static func line(for node: SimulatorAccessibilityNode) -> String {
		var parts = [node.role]
		if let label = node.label {
			parts.append(quoted(label))
		}
		if let value = node.value, value != node.label {
			parts.append("value=\(quoted(value))")
		}
		if let identifier = node.identifier {
			parts.append("id=\(identifier)")
		}
		let frame = node.frame
		parts.append(
			"frame=(\(rounded(frame.minX)),\(rounded(frame.minY)),\(rounded(frame.width)),\(rounded(frame.height)))"
		)
		let point = node.activationPoint
		if point != CGPoint(x: frame.midX, y: frame.midY) {
			parts.append("tap=(\(rounded(point.x)),\(rounded(point.y)))")
		}
		if !node.isEnabled {
			parts.append("disabled")
		}
		return parts.joined(separator: " ")
	}

	private static func quoted(_ text: String) -> String {
		var flattened = text
			.replacingOccurrences(of: "\\", with: "\\\\")
			.replacingOccurrences(of: "\"", with: "\\\"")
			.replacingOccurrences(of: "\n", with: "\\n")
		if flattened.count > 200 {
			flattened = String(flattened.prefix(200)) + "…"
		}
		return "\"\(flattened)\""
	}

	private static func rounded(_ value: CGFloat) -> String {
		String(Int(value.rounded()))
	}
}
