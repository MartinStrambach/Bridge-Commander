import Foundation

/// A point on Earth, in degrees.
public struct SimulatorCoordinate: Equatable, Sendable {
	public var latitude: Double
	public var longitude: Double

	public init(latitude: Double, longitude: Double) {
		self.latitude = latitude
		self.longitude = longitude
	}

	var isValid: Bool {
		(-90...90).contains(latitude) && (-180...180).contains(longitude)
	}

	/// "lat,lon" as `simctl location` takes it: "." for decimals whatever the locale, which
	/// `String(format:)` without a locale gives.
	var simctlArgument: String {
		String(format: "%.6f,%.6f", latitude, longitude)
	}
}

/// What to do with the device's simulated location — `simctl location`'s actions.
public enum SimulatorLocationCommand: Equatable, Sendable {
	/// Stay at one point.
	case set(SimulatorCoordinate)
	/// Move along the waypoints at `speed` metres per second (simctl's default, 20, when `nil`),
	/// with an update every second.
	case route([SimulatorCoordinate], speed: Double?)
	/// One of the runtime's built-in scenarios ("City Run", "Freeway Drive"…).
	case scenario(String)
	/// Stop any route or scenario and drop the simulated location.
	case clear

	/// Fixed points the pane offers as shortcuts, besides the scenarios.
	public static let places: [(name: String, coordinate: SimulatorCoordinate)] = [
		("Prague", SimulatorCoordinate(latitude: 50.087_5, longitude: 14.421_3)), // Old Town Square
	]

	/// Simulator.app's Features ▸ Location scenarios, which the iOS 27 runtime lists.
	public static let knownScenarios = ["Apple", "City Run", "City Bicycle Ride", "Freeway Drive"]

	/// The `simctl` arguments that carry the command out, or why it cannot be.
	func simctlArguments(udid: String) throws(SimulatorError) -> [String] {
		switch self {
		case let .set(coordinate):
			guard coordinate.isValid else {
				throw .invalidLocation("\(coordinate.latitude), \(coordinate.longitude) is not a coordinate: latitude must be within ±90 and longitude within ±180.")
			}
			return ["location", udid, "set", coordinate.simctlArgument]
		case let .route(waypoints, speed):
			guard waypoints.count >= 2 else {
				throw .invalidLocation("A route needs at least two waypoints.")
			}
			if let invalid = waypoints.first(where: { !$0.isValid }) {
				throw .invalidLocation("Waypoint \(invalid.latitude), \(invalid.longitude) is not a coordinate.")
			}
			var arguments = ["location", udid, "start"]
			if let speed {
				guard speed > 0, speed.isFinite else {
					throw .invalidLocation("The speed must be more than 0 metres per second.")
				}
				arguments.append(String(format: "--speed=%.2f", speed))
			}
			return arguments + waypoints.map(\.simctlArgument)
		case let .scenario(name):
			guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
				throw .invalidLocation("No scenario named.")
			}
			return ["location", udid, "run", name]
		case .clear:
			return ["location", udid, "clear"]
		}
	}
}
