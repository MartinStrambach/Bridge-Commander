import CoreGraphics
import Testing
@testable import SimulatorFeature

struct SimulatorAccessibilityFormatterTests {
	private func frame(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
		CGRect(x: x, y: y, width: width, height: height)
	}

	@Test
	func emptyContainersAreLeftOutAndTheirChildrenMovedUp() {
		let tree = SimulatorAccessibilityNode(
			role: "Application",
			label: "Demo",
			frame: frame(0, 0, 402, 874),
			children: [
				SimulatorAccessibilityNode(role: "Group", frame: frame(0, 0, 402, 400), children: [
					SimulatorAccessibilityNode(role: "StaticText", label: "Title", frame: frame(20, 60, 200, 30)),
					SimulatorAccessibilityNode(role: "Button", identifier: "close", frame: frame(350.4, 60, 30, 30)),
				]),
				SimulatorAccessibilityNode(role: "Group", label: "Card", frame: frame(0, 400, 402, 200), children: [
					SimulatorAccessibilityNode(role: "TextField", value: "hello", frame: frame(20, 420, 300, 40), isEnabled: false),
				]),
				SimulatorAccessibilityNode(role: "Image", label: "Hidden", frame: .zero),
			]
		)

		#expect(SimulatorAccessibilityFormatter.describe(tree: tree) == """
		"Demo", 5 elements. frame=(x,y,width,height) in points; tap an element's centre to activate it.
		Application "Demo" frame=(0,0,402,874)
		  StaticText "Title" frame=(20,60,200,30)
		  Button id=close frame=(350,60,30,30)
		  Group "Card" frame=(0,400,402,200)
		    TextField value="hello" frame=(20,420,300,40) disabled
		""")
	}

	@Test
	func labelsAreQuotedOnOneLine() {
		let node = SimulatorAccessibilityNode(role: "StaticText", label: "Say \"hi\"\nnow", value: "Say \"hi\"\nnow", frame: frame(0, 0, 1, 1))
		#expect(SimulatorAccessibilityFormatter.line(for: node) == #"StaticText "Say \"hi\"\nnow" frame=(0,0,1,1)"#)
	}

	@Test
	func pinchFingersSpreadOrCloseAboutTheCentre() {
		let zoomIn = SimulatorHost.pinchFingers(center: CGPoint(x: 200, y: 400), scale: 2, rotationDegrees: 0)
		#expect(zoomIn.start == FingerPair(CGPoint(x: 170, y: 400), CGPoint(x: 230, y: 400)))
		#expect(zoomIn.end == FingerPair(CGPoint(x: 140, y: 400), CGPoint(x: 260, y: 400)))

		let zoomOut = SimulatorHost.pinchFingers(center: CGPoint(x: 200, y: 400), scale: 0.5, rotationDegrees: 0)
		#expect(zoomOut.start == FingerPair(CGPoint(x: 140, y: 400), CGPoint(x: 260, y: 400)))
		#expect(zoomOut.end == FingerPair(CGPoint(x: 170, y: 400), CGPoint(x: 230, y: 400)))

		let turn = SimulatorHost.pinchFingers(center: .zero, scale: 1, rotationDegrees: 90)
		#expect(abs(turn.end.second.x) < 0.0001)
		#expect(abs(turn.end.second.y - 30) < 0.0001)
	}
}
