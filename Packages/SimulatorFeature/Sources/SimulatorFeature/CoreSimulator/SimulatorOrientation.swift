import CoreGraphics
import ImageIO
import Foundation

/// Which way the simulated device is held, as Simulator.app's Device ▸ Orientation sets it.
///
/// This is the physical orientation. The interface follows it only when the frontmost app supports
/// it — an iPhone home screen stays portrait, and Face ID iPhones never turn their interface upside
/// down — so what the screen shows is `SimulatorScreenRotation`, read separately.
public enum SimulatorDeviceOrientation: String, CaseIterable, Equatable, Sendable {
	case portrait
	/// Turned a quarter counterclockwise: the top of the device, and the sensor housing, on the left.
	case landscapeLeft = "landscape_left"
	/// Turned a quarter clockwise: the top of the device on the right.
	case landscapeRight = "landscape_right"
	case portraitUpsideDown = "portrait_upside_down"

	/// The value of the GSEvent that rotates the device (`PurpleWorkspacePort`). These are
	/// `UIDeviceOrientation`'s numbers: 3 makes the guest report `landscapeLeft` (checked live,
	/// 2026-10-07), although idb names that value by the interface orientation it produces.
	var purpleValue: UInt32 {
		switch self {
		case .portrait:
			1
		case .portraitUpsideDown:
			2
		case .landscapeLeft:
			3
		case .landscapeRight:
			4
		}
	}

	/// The guest's name for an orientation, as its orientation service reports it
	/// (`currentDeviceOrientation`). `faceUp`, `faceDown` and `unknown` have no case here.
	init?(guestName: String) {
		switch guestName {
		case "portrait":
			self = .portrait
		case "portraitUpsideDown":
			self = .portraitUpsideDown
		case "landscapeLeft":
			self = .landscapeLeft
		case "landscapeRight":
			self = .landscapeRight
		default:
			return nil
		}
	}

	/// After turning the device a quarter counterclockwise, as Simulator.app's "Rotate Left".
	public var rotatedLeft: SimulatorDeviceOrientation {
		switch self {
		case .portrait:
			.landscapeLeft
		case .landscapeLeft:
			.portraitUpsideDown
		case .portraitUpsideDown:
			.landscapeRight
		case .landscapeRight:
			.portrait
		}
	}

	/// After turning the device a quarter clockwise, as Simulator.app's "Rotate Right".
	public var rotatedRight: SimulatorDeviceOrientation {
		switch self {
		case .portrait:
			.landscapeRight
		case .landscapeRight:
			.portraitUpsideDown
		case .portraitUpsideDown:
			.landscapeLeft
		case .landscapeLeft:
			.portrait
		}
	}

	/// The screen rotation an app that supports this orientation lays its interface out in.
	public var screenRotation: SimulatorScreenRotation {
		switch self {
		case .portrait:
			.upright
		case .landscapeLeft:
			.counterclockwise
		case .landscapeRight:
			.clockwise
		case .portraitUpsideDown:
			.upsideDown
		}
	}

	public var label: String {
		switch self {
		case .portrait:
			"portrait"
		case .landscapeLeft:
			"landscape left"
		case .landscapeRight:
			"landscape right"
		case .portraitUpsideDown:
			"portrait upside down"
		}
	}
}

/// How the interface on the screen is turned relative to the panel, which is portrait.
///
/// The simulator's framebuffer and its digitizer stay in the panel's native, portrait space
/// whatever the rotation: a landscape app is drawn sideways into a portrait surface, and touches
/// are normalized to the portrait panel. Accessibility frames, by contrast, come back in the
/// interface's own space, as the app lays itself out. The tools and the pane work in the
/// interface's space — what a person holding the device sees, and what the model sees in a
/// screenshot — so every point crosses into native space here on its way in. Names and
/// transforms match idb's `SimulatorDisplayGeometry`; verified live for both landscapes
/// (2026-10-07).
public enum SimulatorScreenRotation: String, Equatable, Sendable {
	/// The interface is the panel's way up.
	case upright
	/// The interface is the panel turned a quarter clockwise (the device held landscape right).
	case clockwise
	case upsideDown
	/// The interface is the panel turned a quarter counterclockwise (the device held landscape left).
	case counterclockwise

	/// From the main screen's `uiOrientation` property (`-[SimScreen screenProperties]`), which
	/// follows the interface, not the device. Values found live on CoreSimulator 1171.7: 1 portrait,
	/// 3 landscape with the top of the device on the right, 4 with it on the left; 2 assumed upside
	/// down. Anything else is treated as upright.
	init(uiOrientation: UInt) {
		switch uiOrientation {
		case 2:
			self = .upsideDown
		case 3:
			self = .clockwise
		case 4:
			self = .counterclockwise
		default:
			self = .upright
		}
	}

	/// Whether width and height trade places.
	public var isLandscape: Bool {
		self == .clockwise || self == .counterclockwise
	}

	public var label: String {
		isLandscape ? "landscape" : self == .upsideDown ? "portrait upside down" : "portrait"
	}

	/// The size of the interface for a panel of `nativeSize`.
	public func displayedSize(native nativeSize: CGSize) -> CGSize {
		isLandscape ? CGSize(width: nativeSize.height, height: nativeSize.width) : nativeSize
	}

	/// A point in the interface's space as a point on the panel, for a panel of `nativeSize`
	/// (both in the same unit: points, pixels, or 1×1 for normalized coordinates).
	public func nativePoint(fromDisplayed point: CGPoint, nativeSize: CGSize) -> CGPoint {
		switch self {
		case .upright:
			point
		case .clockwise:
			CGPoint(x: point.y, y: nativeSize.height - point.x)
		case .upsideDown:
			CGPoint(x: nativeSize.width - point.x, y: nativeSize.height - point.y)
		case .counterclockwise:
			CGPoint(x: nativeSize.width - point.y, y: point.x)
		}
	}

	/// The inverse of `nativePoint(fromDisplayed:nativeSize:)`.
	public func displayedPoint(fromNative point: CGPoint, nativeSize: CGSize) -> CGPoint {
		switch self {
		case .upright:
			point
		case .clockwise:
			CGPoint(x: nativeSize.height - point.y, y: point.x)
		case .upsideDown:
			CGPoint(x: nativeSize.width - point.x, y: nativeSize.height - point.y)
		case .counterclockwise:
			CGPoint(x: point.y, y: nativeSize.width - point.x)
		}
	}

	/// The turn, in radians, that brings the portrait framebuffer upright on screen, in a y-down
	/// (flipped) coordinate space where a positive angle turns clockwise.
	var uprightingAngle: CGFloat {
		switch self {
		case .upright:
			0
		case .clockwise:
			.pi / 2
		case .upsideDown:
			.pi
		case .counterclockwise:
			-.pi / 2
		}
	}

	/// The EXIF orientation that, applied to the portrait framebuffer image, gives the interface
	/// upright (`CIImage.oriented(_:)`).
	var framebufferImageOrientation: CGImagePropertyOrientation {
		switch self {
		case .upright:
			.up
		case .clockwise:
			.right
		case .upsideDown:
			.down
		case .counterclockwise:
			.left
		}
	}
}
