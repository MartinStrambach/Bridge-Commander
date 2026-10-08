import CoreGraphics
import Foundation

/// A simulator device as CoreSimulator describes it.
public struct SimulatorDevice: Identifiable, Equatable, Sendable {
	/// `SimDeviceState`. Only the states this package acts on get a case of their own.
	public enum State: Equatable, Sendable {
		case shutdown
		case booting
		case booted
		case shuttingDown
		case other

		init(rawValue: UInt) {
			switch rawValue {
			case 1:
				self = .shutdown
			case 2:
				self = .booting
			case 3:
				self = .booted
			case 4:
				self = .shuttingDown
			default:
				self = .other
			}
		}

		var label: String {
			switch self {
			case .shutdown:
				"Shutdown"
			case .booting:
				"Booting"
			case .booted:
				"Booted"
			case .shuttingDown:
				"Shutting Down"
			case .other:
				"Unavailable"
			}
		}
	}

	/// The device's UDID, uppercased as `simctl` prints it.
	public let id: String
	public let name: String
	/// The runtime's display name, e.g. "iOS 27.0".
	public let runtimeName: String
	public var state: State
	/// The screen in pixels, portrait: the panel's native size, whatever the rotation. The screen
	/// the device shows — an open iPhone Duo's inner panel, else the main screen.
	public let screenPixelSize: CGSize
	public let screenScale: CGFloat
	/// How the interface is turned on the panel, when the device was read. Always upright for a
	/// device that is not booted.
	public var rotation: SimulatorScreenRotation
	/// Whether the device is open, for one that folds (the iPhone Duo); nil for one that does not.
	public let fold: SimulatorFold?
	/// The ID of the screen shown when it is not the main one: an open iPhone Duo's inner panel.
	/// Also tells the pane to attach to another screen when it changes.
	public let screenID: UInt32?
	/// The interface's rotation on the screen shown while the device is held portrait: upright,
	/// but a quarter turn clockwise on an open iPhone Duo's inner panel, which is mounted turned.
	public let portraitRotation: SimulatorScreenRotation

	public init(
		id: String,
		name: String,
		runtimeName: String,
		state: State,
		screenPixelSize: CGSize,
		screenScale: CGFloat,
		rotation: SimulatorScreenRotation = .upright,
		fold: SimulatorFold? = nil,
		screenID: UInt32? = nil,
		portraitRotation: SimulatorScreenRotation = .upright
	) {
		self.id = id
		self.name = name
		self.runtimeName = runtimeName
		self.state = state
		self.screenPixelSize = screenPixelSize
		self.screenScale = screenScale
		self.rotation = rotation
		self.fold = fold
		self.screenID = screenID
		self.portraitRotation = portraitRotation
	}

	/// The interface's rotation when the device is held `orientation` and the app follows it.
	public func interfaceRotation(for orientation: SimulatorDeviceOrientation) -> SimulatorScreenRotation {
		orientation.screenRotation.adding(portraitRotation)
	}

	/// The panel in points, portrait.
	public var nativePointSize: CGSize {
		guard screenScale > 0 else {
			return screenPixelSize
		}
		return CGSize(width: screenPixelSize.width / screenScale, height: screenPixelSize.height / screenScale)
	}

	/// The screen in points as the interface is laid out — landscape when the app is — which is the
	/// coordinate space the MCP tools and screenshots use, and the one an app's layout is written in.
	public var screenPointSize: CGSize {
		rotation.displayedSize(native: nativePointSize)
	}

	/// The screen in pixels as the interface is laid out, for the pane's aspect ratio.
	public var displayedPixelSize: CGSize {
		rotation.displayedSize(native: screenPixelSize)
	}

	public var isBooted: Bool {
		state == .booted
	}

	/// A point in screen points (interface space, top-left origin) as the normalized ratio the
	/// digitizer takes, which is of the portrait panel whatever the rotation. `nil` for a point
	/// outside the screen.
	public func normalizedPoint(x: Double, y: Double) -> CGPoint? {
		let size = screenPointSize
		guard size.width > 0, size.height > 0, x >= 0, y >= 0, x <= size.width, y <= size.height else {
			return nil
		}
		return normalizedPoint(clamping: CGPoint(x: x, y: y))
	}

	/// Like `normalizedPoint(x:y:)`, with a point off the screen moved to its edge.
	func normalizedPoint(clamping point: CGPoint) -> CGPoint {
		let size = screenPointSize
		let clamped = CGPoint(x: min(max(point.x, 0), size.width), y: min(max(point.y, 0), size.height))
		let unit = CGSize(width: 1, height: 1)
		let displayed = CGPoint(x: clamped.x / max(size.width, 1), y: clamped.y / max(size.height, 1))
		return rotation.nativePoint(fromDisplayed: displayed, nativeSize: unit)
	}

	/// A point in screen points (interface space) as a point on the portrait panel, in points —
	/// what accessibility hit-testing takes.
	func nativePoint(_ point: CGPoint) -> CGPoint {
		rotation.nativePoint(fromDisplayed: point, nativeSize: nativePointSize)
	}
}

public enum SimulatorError: Error, Equatable, LocalizedError, Sendable {
	case frameworkUnavailable(String)
	case unsupportedCoreSimulator(version: String)
	case deviceNotFound(String)
	case noBootedDevice
	case deviceNotBooted(String)
	case noFramebuffer
	case inputUnavailable(String)
	case pointOutsideScreen(x: Double, y: Double, width: Double, height: Double)
	case untypeableText(String)
	case unknownKey(String)
	case accessibilityUnavailable(String)
	case commandFailed(String)
	case invalidLocation(String)
	case memoryWarningUnavailable
	case alreadyRecording(device: String, path: String)
	case notRecording(String)
	case recordingFailed(String)
	case notFoldable(String)

	public var errorDescription: String? {
		switch self {
		case let .frameworkUnavailable(detail):
			"CoreSimulator could not be loaded (is Xcode installed?): \(detail)"
		case let .unsupportedCoreSimulator(version):
			"This CoreSimulator (\(version)) predates the dtuhidd input service; input needs Xcode 27 or later."
		case let .deviceNotFound(udid):
			"No simulator with UDID \(udid)."
		case .noBootedDevice:
			"No iOS simulator is booted. Boot one (`xcrun simctl boot <udid>`; list_devices shows them) and try again."
		case let .deviceNotBooted(name):
			"\(name) is not booted."
		case .noFramebuffer:
			"The simulator's screen is not available yet; it may still be booting."
		case let .inputUnavailable(detail):
			"Could not reach the simulator's input service (dtuhidd): \(detail)"
		case let .pointOutsideScreen(x, y, width, height):
			"(\(x), \(y)) is outside the screen, which is \(width)×\(height) points."
		case let .untypeableText(characters):
			"These characters cannot be typed on the simulated US keyboard: \(characters). Put the text on the simulator's pasteboard with `xcrun simctl pbcopy <udid>` and press cmd+v instead."
		case let .unknownKey(key):
			"Unknown key \"\(key)\"."
		case let .accessibilityUnavailable(detail):
			"The simulator's accessibility tree could not be read: \(detail)"
		case let .commandFailed(detail):
			detail
		case let .invalidLocation(detail):
			detail
		case .memoryWarningUnavailable:
			"This CoreSimulator cannot simulate a memory warning (SimDevice has no simulateMemoryWarning)."
		case let .alreadyRecording(device, path):
			"\(device) is already being recorded, to \(path). Stop that recording first."
		case let .notRecording(device):
			"\(device) is not being recorded."
		case let .recordingFailed(detail):
			"The recording failed: \(detail)"
		case let .notFoldable(name):
			"\(name) does not fold; only the iPhone Duo does."
		}
	}
}
