import CoreGraphics
import Testing
@testable import SimulatorFeature

struct SimulatorOrientationTests {
	/// iPhone Air's panel in points.
	private static let panel = CGSize(width: 420, height: 912)
	private static let rotations: [SimulatorScreenRotation] = [.upright, .clockwise, .upsideDown, .counterclockwise]

	@Test
	func landscapeSwapsTheDisplayedSize() {
		#expect(SimulatorScreenRotation.upright.displayedSize(native: Self.panel) == Self.panel)
		#expect(SimulatorScreenRotation.upsideDown.displayedSize(native: Self.panel) == Self.panel)
		#expect(SimulatorScreenRotation.clockwise.displayedSize(native: Self.panel) == CGSize(width: 912, height: 420))
		#expect(SimulatorScreenRotation.counterclockwise.displayedSize(native: Self.panel) == CGSize(width: 912, height: 420))
	}

	/// Where the interface's top-left corner lies on the portrait panel. With the device turned
	/// counterclockwise (sensor housing on the left), the interface's top left is the panel's top
	/// right; turned clockwise, its bottom left — as seen in the framebuffer on 2026-10-07.
	@Test
	func theInterfacesTopLeftCornerOnThePanel() {
		let corner = CGPoint.zero
		#expect(SimulatorScreenRotation.upright.nativePoint(fromDisplayed: corner, nativeSize: Self.panel) == .zero)
		#expect(SimulatorScreenRotation.counterclockwise.nativePoint(fromDisplayed: corner, nativeSize: Self.panel) == CGPoint(x: 420, y: 0))
		#expect(SimulatorScreenRotation.clockwise.nativePoint(fromDisplayed: corner, nativeSize: Self.panel) == CGPoint(x: 0, y: 912))
		#expect(SimulatorScreenRotation.upsideDown.nativePoint(fromDisplayed: corner, nativeSize: Self.panel) == CGPoint(x: 420, y: 912))
	}

	/// A point measured live: Safari's "Privacy Report" switch at (738, 208) in a landscape-left
	/// screenshot is at (212, 738) on the panel, where the tap that toggled it landed.
	@Test
	func aLiveLandscapeLeftTap() {
		let native = SimulatorScreenRotation.counterclockwise.nativePoint(fromDisplayed: CGPoint(x: 738, y: 208), nativeSize: Self.panel)
		#expect(native == CGPoint(x: 212, y: 738))
	}

	@Test
	func displayedAndNativePointsRoundTrip() {
		let points = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 30), CGPoint(x: 400, y: 900), CGPoint(x: 12.5, y: 600.25)]
		for rotation in Self.rotations {
			let displayed = rotation.displayedSize(native: Self.panel)
			for point in points where point.x <= displayed.width && point.y <= displayed.height {
				let native = rotation.nativePoint(fromDisplayed: point, nativeSize: Self.panel)
				#expect((0...Self.panel.width).contains(native.x) && (0...Self.panel.height).contains(native.y))
				#expect(rotation.displayedPoint(fromNative: native, nativeSize: Self.panel) == point)
			}
		}
	}

	@Test
	func theCentreStaysPut() {
		for rotation in Self.rotations {
			let displayed = rotation.displayedSize(native: Self.panel)
			let centre = CGPoint(x: displayed.width / 2, y: displayed.height / 2)
			#expect(rotation.nativePoint(fromDisplayed: centre, nativeSize: Self.panel) == CGPoint(x: 210, y: 456))
		}
	}

	@Test
	func screenPropertiesOrientationValues() {
		#expect(SimulatorScreenRotation(uiOrientation: 1) == .upright)
		#expect(SimulatorScreenRotation(uiOrientation: 2) == .upsideDown)
		#expect(SimulatorScreenRotation(uiOrientation: 3) == .clockwise)
		#expect(SimulatorScreenRotation(uiOrientation: 4) == .counterclockwise)
		#expect(SimulatorScreenRotation(uiOrientation: 0) == .upright)
	}

	@Test
	func turningLeftOrRightGoesRoundTheFourOrientations() {
		var orientation = SimulatorDeviceOrientation.portrait
		var seen: [SimulatorDeviceOrientation] = []
		for _ in 0..<4 {
			orientation = orientation.rotatedLeft
			seen.append(orientation)
		}
		#expect(seen == [.landscapeLeft, .portraitUpsideDown, .landscapeRight, .portrait])
		for orientation in SimulatorDeviceOrientation.allCases {
			#expect(orientation.rotatedLeft.rotatedRight == orientation)
		}
	}

	@Test
	func deviceOrientationsMapToTheGuestAndThePurpleEvent() {
		#expect(SimulatorDeviceOrientation.allCases.map(\.purpleValue) == [1, 3, 4, 2])
		#expect(SimulatorDeviceOrientation(guestName: "landscapeLeft") == .landscapeLeft)
		#expect(SimulatorDeviceOrientation(guestName: "portraitUpsideDown") == .portraitUpsideDown)
		#expect(SimulatorDeviceOrientation(guestName: "faceUp") == nil)
		#expect(SimulatorDeviceOrientation.landscapeLeft.screenRotation == .counterclockwise)
		#expect(SimulatorDeviceOrientation.landscapeRight.screenRotation == .clockwise)
	}

	@Test
	func aRotatedDeviceTakesPointsInTheInterfacesSpace() {
		let device = SimulatorDevice(
			id: "AAAA",
			name: "iPhone Air",
			runtimeName: "iOS 27.0",
			state: .booted,
			screenPixelSize: CGSize(width: 1260, height: 2736),
			screenScale: 3,
			rotation: .clockwise
		)
		#expect(device.screenPointSize == CGSize(width: 912, height: 420))
		#expect(device.nativePointSize == Self.panel)
		#expect(device.displayedPixelSize == CGSize(width: 2736, height: 1260))
		// Landscape x beyond the portrait width is on screen; portrait y beyond the height is not.
		#expect(device.normalizedPoint(x: 900, y: 10) != nil)
		#expect(device.normalizedPoint(x: 10, y: 500) == nil)
		// The interface's top right is the panel's top left when turned clockwise.
		#expect(device.normalizedPoint(x: 912, y: 0) == CGPoint(x: 0, y: 0))
		#expect(device.normalizedPoint(clamping: CGPoint(x: -50, y: 1000)) == CGPoint(x: 1, y: 1))
		#expect(device.nativePoint(CGPoint(x: 456, y: 210)) == CGPoint(x: 210, y: 456))
	}

	@Test
	func thePurpleOrientationMessage() {
		let bytes = SimulatorHost.purpleMessage(event: 50 | 0x2_0000, value: 3)
		func word(at offset: Int) -> UInt32 {
			(0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[offset + $1]) << (8 * $1) }
		}
		#expect(bytes.count == 112)
		#expect(word(at: 0x00) == 0x13)
		#expect(word(at: 0x04) == 108)
		#expect(word(at: 0x08) == 0)
		#expect(word(at: 0x14) == 0x7B)
		#expect(word(at: 0x18) == 0x2_0032)
		#expect(word(at: 0x48) == 4)
		#expect(word(at: 0x4C) == 3)
	}
}
