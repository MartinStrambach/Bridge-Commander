import CoreGraphics
import Foundation

extension SimulatorHost {
	/// Acts on the frontmost app's element that `query` finds: presses it, sets its value or
	/// scrolls it into view through accessibility. A press the element cannot take becomes a tap on
	/// its centre, which is what a finger would have done.
	public func performElementAction(
		_ action: SimulatorElementAction,
		on query: SimulatorElementQuery,
		device: SimulatorDevice
	) async throws -> SimulatorElementOutcome {
		let result = try await SimulatorAccessibility.shared.perform(
			action,
			on: query,
			device: ObjectBox(object: simDevice(udid: device.id)),
			display: accessibilityDisplay(device)
		)
		switch result {
		case let .done(outcome):
			return outcome
		case let .needsTap(element):
			let centre = CGPoint(x: element.frame.midX, y: element.frame.midY)
			try await tap(device: device, x: centre.x, y: centre.y)
			return SimulatorElementOutcome(element: element, effect: .tappedCentre(centre))
		}
	}
}
