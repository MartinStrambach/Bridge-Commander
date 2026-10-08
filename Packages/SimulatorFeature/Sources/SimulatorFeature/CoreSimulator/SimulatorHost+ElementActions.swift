import CoreGraphics
import Foundation

extension SimulatorHost {
	/// Acts on the frontmost app's element that `query` finds: presses it, sets its value or
	/// scrolls it into view through accessibility. A press the element cannot take becomes a tap at
	/// its activation point, which is what a finger would have done.
	public func performElementAction(
		_ action: SimulatorElementAction,
		on query: SimulatorElementQuery,
		device: SimulatorDevice
	) async throws -> SimulatorElementOutcome {
		let result = try await SimulatorAccessibility.shared.perform(
			action,
			on: query,
			device: ObjectBox(object: simDevice(udid: device.id))
		)
		switch result {
		case let .done(outcome):
			return outcome
		case let .needsTap(element):
			let point = element.activationPoint
			try await tap(device: device, x: point.x, y: point.y)
			return SimulatorElementOutcome(element: element, effect: .tapped(point))
		}
	}
}
