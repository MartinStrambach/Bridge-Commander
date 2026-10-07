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
	/// The main screen in pixels, portrait.
	public let screenPixelSize: CGSize
	public let screenScale: CGFloat

	public init(
		id: String,
		name: String,
		runtimeName: String,
		state: State,
		screenPixelSize: CGSize,
		screenScale: CGFloat
	) {
		self.id = id
		self.name = name
		self.runtimeName = runtimeName
		self.state = state
		self.screenPixelSize = screenPixelSize
		self.screenScale = screenScale
	}

	/// The main screen in points — the coordinate space the MCP tools and screenshots use, and the
	/// one an app's layout is written in.
	public var screenPointSize: CGSize {
		guard screenScale > 0 else {
			return screenPixelSize
		}
		return CGSize(width: screenPixelSize.width / screenScale, height: screenPixelSize.height / screenScale)
	}

	public var isBooted: Bool {
		state == .booted
	}

	/// A point in screen points as the normalized, top-left-origin ratio the digitizer takes.
	/// `nil` for a point outside the screen.
	public func normalizedPoint(x: Double, y: Double) -> CGPoint? {
		let size = screenPointSize
		guard size.width > 0, size.height > 0, x >= 0, y >= 0, x <= size.width, y <= size.height else {
			return nil
		}
		return CGPoint(x: x / size.width, y: y / size.height)
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
	case commandFailed(String)

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
		case let .commandFailed(detail):
			detail
		}
	}
}
