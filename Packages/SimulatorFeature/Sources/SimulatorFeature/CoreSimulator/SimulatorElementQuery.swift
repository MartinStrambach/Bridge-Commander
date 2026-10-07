import CoreGraphics
import Foundation

/// Which element of the frontmost app's accessibility tree an action is for, found by what it is
/// rather than where it is — so the action still lands after a layout change, and the model does
/// not have to read frames off a screenshot.
public nonisolated struct SimulatorElementQuery: Equatable, Sendable {
	public var identifier: String?
	public var label: String?
	/// Roles without the "AX" prefix ("Button", "TextField"), compared ignoring case; empty for any.
	public var roles: Set<String>
	/// Picks one of several matches, from 0 in tree order (top to bottom, roughly).
	public var index: Int?

	public init(identifier: String? = nil, label: String? = nil, roles: Set<String> = [], index: Int? = nil) {
		self.identifier = identifier
		self.label = label
		self.roles = roles
		self.index = index
	}

	/// The roles `set_value` looks among when it is given nothing else to go on.
	public static let textEntryRoles: Set<String> = ["TextField", "SearchField", "SecureTextField", "TextArea", "ComboBox"]

	/// The position in `candidates` (a flattened tree) of the element the query means.
	///
	/// Tiers, the first with any match winning: exact identifier, exact label, label equal ignoring
	/// case, label containing the text ignoring case — so "Sign In" finds the button labelled
	/// exactly that even when "Sign In with Apple" is on screen too. Among several matches of one
	/// tier, `preferredRoles` (the controls, for a press) are kept over the rest, since a button and
	/// a heading often share a label. The application element itself is never a candidate.
	func match(
		in candidates: [SimulatorAccessibilityNode],
		preferring preferredRoles: Set<String> = []
	) throws(SimulatorElementError) -> Int {
		let wantedRoles = Set(roles.map { Self.bareRole($0).lowercased() })
		let pool = candidates.indices.filter { position in
			let role = candidates[position].role
			return role != "Application" && (wantedRoles.isEmpty || wantedRoles.contains(role.lowercased()))
		}

		var tiers: [[Int]] = []
		if let identifier {
			tiers.append(pool.filter { candidates[$0].identifier == identifier })
		}
		if let label {
			tiers.append(pool.filter { candidates[$0].label == label })
			tiers.append(pool.filter { candidates[$0].label?.compare(label, options: Self.looseComparison) == .orderedSame })
			tiers.append(pool.filter { candidates[$0].label?.range(of: label, options: Self.looseComparison) != nil })
		}
		if identifier == nil, label == nil {
			tiers.append(pool)
		}

		guard var matches = tiers.first(where: { !$0.isEmpty }) else {
			let onScreen = candidates.filter { $0.role != "Application" && SimulatorAccessibilityFormatter.isInformative($0) }
			throw .notFound(
				query: summary,
				onScreen: onScreen.prefix(Self.listedLimit).map(SimulatorAccessibilityFormatter.line(for:)),
				more: max(onScreen.count - Self.listedLimit, 0)
			)
		}
		if matches.count > 1 {
			let preferred = matches.filter { preferredRoles.contains(candidates[$0].role) }
			if !preferred.isEmpty {
				matches = preferred
			}
		}

		let lines = matches.prefix(Self.listedLimit).enumerated().map { offset, position in
			"[\(offset)] \(SimulatorAccessibilityFormatter.line(for: candidates[position]))"
		}
		if let index {
			guard matches.indices.contains(index) else {
				throw .indexOutOfRange(index: index, query: summary, count: matches.count, matches: lines)
			}
			return matches[index]
		}
		guard matches.count == 1 else {
			throw .ambiguous(query: summary, count: matches.count, matches: lines)
		}
		return matches[0]
	}

	/// What the query asks for, as the messages quote it.
	var summary: String {
		var parts: [String] = []
		if let identifier {
			parts.append("identifier \"\(identifier)\"")
		}
		if let label {
			parts.append("label \"\(label)\"")
		}
		if !roles.isEmpty {
			parts.append("role \(roles.sorted().joined(separator: "/"))")
		}
		return parts.isEmpty ? "any element" : parts.joined(separator: " or ")
	}

	/// Bounds the candidate lists in messages; a model refines its query rather than reading 300 lines.
	static let listedLimit = 40

	private static let looseComparison: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

	private static func bareRole(_ role: String) -> String {
		role.hasPrefix("AX") ? String(role.dropFirst(2)) : role
	}
}

extension SimulatorAccessibilityNode {
	/// The tree in depth-first order with each node's children dropped — the candidates a query
	/// is matched against.
	public func flattened() -> [SimulatorAccessibilityNode] {
		var nodes: [SimulatorAccessibilityNode] = []
		func visit(_ node: SimulatorAccessibilityNode) {
			var own = node
			own.children = []
			nodes.append(own)
			node.children.forEach(visit)
		}
		visit(self)
		return nodes
	}
}

/// What to do to the element a query finds.
public nonisolated enum SimulatorElementAction: Equatable, Sendable {
	/// AXPress (the guest's `accessibilityActivate`), or a tap on the element's centre when it has
	/// no press action or refuses it.
	case press
	/// Sets the element's AXValue, as typing would leave it.
	case setValue(String)
	/// AXScrollToVisible: the enclosing scroll views move until the element is on screen.
	case scrollToVisible

	/// Kept over other matches with the same label.
	var preferredRoles: Set<String> {
		switch self {
		case .press:
			SimulatorAccessibilityFormatter.controlRoles
		case .setValue:
			SimulatorElementQuery.textEntryRoles
		case .scrollToVisible:
			[]
		}
	}
}

/// What an element action did, for the tool's reply.
public nonisolated struct SimulatorElementOutcome: Equatable, Sendable {
	public enum Effect: Equatable, Sendable {
		/// The accessibility press was accepted.
		case pressed
		/// There was no accessibility press, or it was refused, so the element's centre was tapped.
		case tappedCentre(CGPoint)
		/// The value was set; `readBack` is what the element reports afterwards.
		case valueSet(readBack: String?)
		/// Scrolled into view; the element's frame afterwards.
		case scrolled(to: CGRect)
	}

	/// The element as it was found, without its children.
	public var element: SimulatorAccessibilityNode
	public var effect: Effect

	public init(element: SimulatorAccessibilityNode, effect: Effect) {
		self.element = element
		self.effect = effect
	}
}

/// Why an element action could not be done. The messages list what is on screen, so the model
/// can refine its query instead of guessing again.
public nonisolated enum SimulatorElementError: Error, Equatable, LocalizedError, Sendable {
	case noCriteria
	case missingValue
	case notFound(query: String, onScreen: [String], more: Int)
	case ambiguous(query: String, count: Int, matches: [String])
	case indexOutOfRange(index: Int, query: String, count: Int, matches: [String])
	case notSettable(element: String)
	case notScrollable(element: String)

	public var errorDescription: String? {
		switch self {
		case .noCriteria:
			return "Give an identifier, a label or a role to find the element by (describe_ui lists them)."
		case .missingValue:
			return "Missing \"value\"."
		case let .notFound(query, onScreen, more):
			guard !onScreen.isEmpty else {
				return "No element matches \(query), and the screen has no labelled elements."
			}
			let rest = more > 0 ? "\n…and \(more) more." : ""
			return "No element matches \(query). Elements on screen:\n" + onScreen.joined(separator: "\n") + rest
		case let .ambiguous(query, count, matches):
			return "\(count) elements match \(query); pass index to pick one:\n" + listing(matches, of: count)
		case let .indexOutOfRange(index, query, count, matches):
			return "index \(index) is out of range; \(count) element\(count == 1 ? "" : "s") match\(count == 1 ? "es" : "") \(query):\n"
				+ listing(matches, of: count)
		case let .notSettable(element):
			return "\(element) does not take a value through accessibility. Tap it and use type_text instead "
				+ "(cmd+a then delete clears what is there)."
		case let .notScrollable(element):
			return "\(element) cannot be scrolled to through accessibility; swipe instead."
		}
	}

	private func listing(_ lines: [String], of count: Int) -> String {
		lines.joined(separator: "\n") + (count > lines.count ? "\n…and \(count - lines.count) more." : "")
	}
}
