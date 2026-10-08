import CoreGraphics
import Foundation
import Testing
@testable import SimulatorFeature

struct SimulatorElementQueryTests {
	private static func node(
		_ role: String,
		_ label: String? = nil,
		id: String? = nil,
		y: CGFloat = 0,
		children: [SimulatorAccessibilityNode] = []
	) -> SimulatorAccessibilityNode {
		SimulatorAccessibilityNode(role: role, label: label, identifier: id, frame: CGRect(x: 20, y: y, width: 100, height: 40), children: children)
	}

	private static let screen = node("Application", "Settings", children: [
		node("Button", "Settings", id: "BackButton", y: 60),
		node("Heading", "General", y: 240),
		node("Group", children: [
			node("Button", "General", id: "settings.general", y: 380),
			node("Button", "About", id: "settings.about", y: 440),
			node("Button", "Sign In with Apple", id: "signin.apple", y: 500),
			node("Button", "Sign In", id: "signin", y: 560),
		]),
		node("TextField", nil, id: "search", y: 890),
		node("StaticText", "general settings", y: 900),
	])

	private let candidates = Self.screen.flattened()

	private func matched(
		_ query: SimulatorElementQuery,
		preferring roles: Set<String> = []
	) throws(SimulatorElementError) -> SimulatorAccessibilityNode {
		candidates[try query.match(in: candidates, preferring: roles)]
	}

	@Test
	func flatteningKeepsTreeOrderAndDropsChildren() {
		#expect(candidates.map(\.role) == [
			"Application", "Button", "Heading", "Group", "Button", "Button", "Button", "Button", "TextField", "StaticText",
		])
		#expect(candidates.allSatisfy { $0.children.isEmpty })
	}

	@Test
	func anExactIdentifierWinsOverLabels() throws {
		let found = try matched(SimulatorElementQuery(identifier: "settings.about", label: "General"))
		#expect(found.label == "About")
	}

	@Test
	func anExactLabelWinsOverOnesContainingIt() throws {
		#expect(try matched(SimulatorElementQuery(label: "Sign In")).identifier == "signin")
		#expect(try matched(SimulatorElementQuery(label: "sign in")).identifier == "signin")
		#expect(try matched(SimulatorElementQuery(label: "apple")).identifier == "signin.apple")
	}

	@Test
	func valuesAreMatchedAfterLabels() throws {
		let fields = Self.node("Application", children: [
			SimulatorAccessibilityNode(role: "TextField", value: "me@example.com", identifier: "email", frame: CGRect(x: 0, y: 0, width: 10, height: 10)),
			SimulatorAccessibilityNode(role: "Switch", label: "Example", value: "1", frame: CGRect(x: 0, y: 20, width: 10, height: 10)),
		]).flattened()
		func found(_ query: SimulatorElementQuery) throws -> String? {
			let node = fields[try query.match(in: fields)]
			return node.identifier ?? node.label
		}
		#expect(try found(SimulatorElementQuery(value: "ME@example.com")) == "email")
		#expect(try found(SimulatorElementQuery(value: "1")) == "Example")
		// A label match wins over a value match.
		#expect(try found(SimulatorElementQuery(label: "example", value: "example")) == "Example")
		#expect(SimulatorElementQuery(value: "nothing").matches(in: fields).isEmpty)
	}

	@Test
	func theApplicationIsNeverACandidate() throws {
		// "Settings" is also the application's label; only the back button is pressable.
		#expect(try matched(SimulatorElementQuery(label: "Settings")).identifier == "BackButton")
	}

	@Test
	func preferredRolesSettleASharedLabel() throws {
		#expect(try matched(SimulatorElementQuery(label: "General"), preferring: ["Button"]).identifier == "settings.general")
		#expect(throws: SimulatorElementError.self) {
			try matched(SimulatorElementQuery(label: "General"))
		}
	}

	@Test
	func severalMatchesAreListedForAnIndex() throws {
		let query = SimulatorElementQuery(label: "general")
		do {
			_ = try matched(query, preferring: [])
			Issue.record("expected ambiguity")
		}
		catch {
			// Exact-ignoring-case finds the heading and the button; the static text only contains it.
			#expect(error == .ambiguous(query: "label \"general\"", count: 2, matches: [
				"[0] Heading \"General\" frame=(20,240,100,40)",
				"[1] Button \"General\" id=settings.general frame=(20,380,100,40)",
			]))
			#expect(error.localizedDescription.hasPrefix("2 elements match label \"general\"; pass index to pick one:\n[0] Heading"))
		}

		var picked = query
		picked.index = 1
		#expect(try matched(picked).identifier == "settings.general")

		picked.index = 2
		#expect(throws: SimulatorElementError.indexOutOfRange(index: 2, query: "label \"general\"", count: 2, matches: [
			"[0] Heading \"General\" frame=(20,240,100,40)",
			"[1] Button \"General\" id=settings.general frame=(20,380,100,40)",
		])) {
			try matched(picked)
		}
	}

	@Test
	func aMissListsWhatIsOnScreen() {
		do {
			_ = try matched(SimulatorElementQuery(identifier: "nope"))
			Issue.record("expected a miss")
		}
		catch {
			guard case let .notFound(query, onScreen, more) = error else {
				Issue.record("unexpected \(error)")
				return
			}
			#expect(query == "identifier \"nope\"")
			#expect(more == 0)
			// Everything informative but the application and the empty group.
			#expect(onScreen.count == 8)
			#expect(onScreen.first == "Button \"Settings\" id=BackButton frame=(20,60,100,40)")
			#expect(error.localizedDescription.hasPrefix("No element matches identifier \"nope\". Elements on screen:\nButton"))
		}
	}

	@Test
	func rolesNarrowAndCanStandAlone() throws {
		let field = try matched(SimulatorElementQuery(roles: SimulatorElementQuery.textEntryRoles))
		#expect(field.identifier == "search")
		#expect(try matched(SimulatorElementQuery(label: "general", roles: ["AXStaticText"])).role == "StaticText")
		#expect(try matched(SimulatorElementQuery(roles: ["button"], index: 4)).identifier == "signin")
	}
}
