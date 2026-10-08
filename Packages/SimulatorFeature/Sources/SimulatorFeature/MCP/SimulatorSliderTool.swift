import CoreGraphics
import Foundation

/// `set_slider`: moves a slider to a percentage of its range, closing the loop on the value it
/// reports rather than trusting where its frame says the thumb is.
///
/// Accessibility cannot set it: iOS reports a slider's value as settable, and `setAccessibilityValue`
/// is accepted and ignored (Settings' Dynamic Type slider, 2026-10-08). The frame is not the track
/// either — that slider's is its whole 362 × 80 pt row, the small and large "A" at its ends included —
/// so where the thumb is can only be guessed. It steps with AXIncrement / AXDecrement as far as they
/// get it (a stepped slider exactly; a continuous one to within half of its 10 % increment), then
/// drags the rest from where the thumb should be, reads the value back, re-measures the track from
/// how far the value moved and drags again. AXe (`cameroncooke/AXe`) only drags, once, with offsets
/// tuned for plain sliders.
nonisolated enum SimulatorSliderTool {
	/// Close enough: a third of a point on a 330 pt track is 0.1 %.
	static let tolerance = 0.01
	static let maximumDrags = 4
	static let maximumSteps = 40

	static func call(
		arguments: JSONValue,
		query: SimulatorElementQuery,
		timeout: Duration,
		device: SimulatorDevice,
		actions: any SimulatorToolActions
	) async throws -> String {
		guard let percent = arguments["value"]?.doubleValue, percent.isFinite, (0...100).contains(percent) else {
			throw SimulatorElementError.invalidSliderTarget
		}
		let target = percent / 100

		var slider = try await SimulatorElementTools.untilFound(timeout: timeout) {
			try await find(query, device: device, actions: actions)
		}
		let found = SimulatorAccessibilityFormatter.line(for: slider)
		guard SimulatorElementQuery.adjustableRoles.contains(slider.role) else {
			throw SimulatorElementError.notASlider(element: found)
		}
		guard var current = SimulatorSliderValue.fraction(from: slider.value) else {
			throw SimulatorElementError.unreadableSlider(element: found)
		}
		let initial = slider.value ?? ""
		let initialFraction = current
		guard abs(current - target) > tolerance else {
			return "\(found) is already at \(format(percent)) %."
		}

		// Step first: nothing touches the screen, so nothing can land beside the thumb — a drag
		// that missed it to the right was the back swipe and left the page (2026-10-08) — and a
		// slider that moves in steps ends exactly on one.
		var steps = 0
		while abs(current - target) > tolerance, steps < maximumSteps {
			let action: SimulatorElementAction = target > current ? .increment : .decrement
			let outcome: SimulatorElementOutcome
			do {
				outcome = try await actions.elementAction(action, on: query, device: device)
			}
			catch SimulatorElementError.notAdjustable {
				break
			}
			steps += 1
			guard case let .valueSet(readBack) = outcome.effect, let value = SimulatorSliderValue.fraction(from: readBack) else {
				break
			}
			// At the end of its range.
			guard abs(value - current) >= 0.002 else {
				break
			}
			if abs(value - target) > abs(current - target) {
				// Overshot by more than it was short: one step back, and the drag does the rest.
				_ = try? await actions.elementAction(action == .increment ? .decrement : .increment, on: query, device: device)
				break
			}
			current = value
		}

		// Drag the rest: a continuous slider's increments are a tenth of its range, so this is under
		// half of that — too short and slow to complete a back swipe if it misses the thumb. Without
		// increments it is the whole way, re-measuring the track after each drag from how far the
		// value moved.
		var track = SimulatorSliderTrack(frame: slider.frame)
		var fingerX = track.x(for: current)
		let y = slider.frame.midY
		let width = device.screenPointSize.width
		for _ in 0..<maximumDrags where abs(current - target) > tolerance {
			let endX = min(max(fingerX + (target - current) * track.width, 1), width - 1)
			try await actions.swipe(
				device: device,
				from: CGPoint(x: fingerX, y: y),
				to: CGPoint(x: endX, y: y),
				duration: .milliseconds(600),
				holdFor: .milliseconds(60)
			)
			do {
				slider = try await find(query, device: device, actions: actions)
			}
			catch SimulatorElementError.notFound {
				throw SimulatorElementError.sliderVanished(element: found)
			}
			guard let value = SimulatorSliderValue.fraction(from: slider.value) else {
				break
			}
			let moved = value - current
			// Nothing moved: the finger missed the thumb, or the slider snapped back to its step.
			guard abs(moved) >= 0.002 else {
				break
			}
			track.calibrate(fingerMoved: endX - fingerX, valueMoved: moved)
			fingerX = endX
			current = value
		}

		slider = try await find(query, device: device, actions: actions)
		let reads = slider.value ?? ""
		guard let final = SimulatorSliderValue.fraction(from: slider.value), abs(final - initialFraction) >= 0.002 else {
			throw SimulatorElementError.sliderDidNotMove(element: found)
		}
		let line = SimulatorAccessibilityFormatter.line(for: slider)
		guard abs(final - target) <= tolerance else {
			return "Moved \(line) from \"\(initial)\" toward \(format(percent)) %: it now reads \"\(reads)\", as close as it goes (it moves in steps)."
		}
		return "Moved \(line) from \"\(initial)\" to \"\(reads)\"."
	}

	private static func find(
		_ query: SimulatorElementQuery,
		device: SimulatorDevice,
		actions: any SimulatorToolActions
	) async throws -> SimulatorAccessibilityNode {
		let candidates = try await actions.accessibilityTree(device: device).flattened()
		return candidates[try query.match(in: candidates, preferring: SimulatorElementQuery.adjustableRoles)]
	}

	private static func format(_ value: Double) -> String {
		value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
	}
}

/// A slider's value as a fraction of its range.
nonisolated enum SimulatorSliderValue {
	/// From the value a slider reports: UIKit and SwiftUI give a localized percentage ("50 %",
	/// "50%", "%50"); a fraction from 0 to 1 is taken as is, a bare number up to 100 as a
	/// percentage. Anything else — a custom value such as "3 stars" — is `nil`.
	static func fraction(from value: String?) -> Double? {
		guard
			let value,
			value.rangeOfCharacter(from: .letters) == nil,
			let range = value.range(of: #"[0-9]+([.,][0-9]+)?"#, options: .regularExpression),
			let number = Double(value[range].replacingOccurrences(of: ",", with: "."))
		else {
			return nil
		}
		let fraction: Double = if value.contains("%") || number > 1 { number / 100 } else { number }
		guard (0...1).contains(fraction) else {
			return nil
		}
		return fraction
	}
}

/// Where along a slider's frame each value is, in points: first assumed to span the frame less a
/// thumb's half-width at each end, then measured from the drags.
nonisolated struct SimulatorSliderTrack: Equatable {
	var minX: Double
	var width: Double
	let frameWidth: Double

	init(frame: CGRect) {
		// A UISlider's thumb is about 28 pt across, its centre stopping half of that short of the ends.
		let inset = min(frame.height / 2, 14)
		minX = frame.minX + inset
		width = max(frame.width - 2 * inset, 1)
		frameWidth = frame.width
	}

	func x(for fraction: Double) -> Double {
		minX + fraction * width
	}

	/// Takes the track's width from a drag that moved the value by `valueMoved` for `fingerMoved`
	/// points. A small move says little — a stepped slider's value jumps by whole steps — so only one
	/// of at least 5 % counts, and the width is kept within reason of the frame's.
	mutating func calibrate(fingerMoved: Double, valueMoved: Double) {
		guard abs(valueMoved) >= 0.05, fingerMoved != 0, (fingerMoved > 0) == (valueMoved > 0) else {
			return
		}
		width = min(max(abs(fingerMoved / valueMoved), frameWidth * 0.3), frameWidth * 1.5)
	}
}
