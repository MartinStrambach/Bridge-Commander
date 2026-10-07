import Foundation

/// How the screen behaved after an action, for a tool to tell the model whether the screenshot it
/// takes next will show the action's result.
enum ScreenSettleResult: Equatable, Sendable {
	/// It changed, then held still for the quiet period. `after` is the time from the end of the
	/// action to that verdict, quiet period included.
	case settled(after: Duration)
	/// Nothing visible changed while it was watched.
	case unchanged(after: Duration)
	/// It was still changing when the wait gave up: a long animation, a spinner, video.
	case stillChanging(after: Duration)
	/// The framebuffer could not be read, so nothing is known.
	case unavailable

	/// A sentence for a tool result.
	var summary: String {
		switch self {
		case let .settled(after):
			"Screen settled after \(Self.milliseconds(after)) ms."
		case let .unchanged(after):
			"No change on screen within \(Self.milliseconds(after)) ms (tiny changes, such as a blinking caret, are ignored)."
		case let .stillChanging(after):
			"Screen still changing after \(Self.milliseconds(after)) ms (animation, loading or video); look again if you need the final state."
		case .unavailable:
			"Could not watch the screen settle."
		}
	}

	private static func milliseconds(_ duration: Duration) -> Int {
		Int((Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15).rounded())
	}
}

/// Decides, from successive fingerprints of the screen, when it has stopped changing.
///
/// Each fingerprint is compared with the last one that counted as a change, not with the one just
/// before it, so a slow fade that moves every sample only a little still adds up to a change. The
/// screen has settled once it stays within tolerance of that reference for `quietPeriod`. Until
/// something has changed, the wait is held open for `responseGrace` instead, since an app can take
/// a frame or two to start reacting; if nothing has changed by then, the result is `unchanged`.
///
/// Tolerances: a cell must move by more than `cellTolerance` — one unit of its mean byte sum,
/// about a quarter of what a single one of its ~190 samples flipping between black and white does
/// — and more than `ignoredCells` cells must move. A blinking caret (which fades, so it changes for
/// ~150 ms twice a second) touches one 16-point column and two or three rows of cells; ignoring
/// four keeps it from holding the wait open after typing or passing for the action's effect. The
/// cost is that a change that small, like a lone checkmark, goes unnoticed — but a tap on a
/// control highlights it, which is large. The status bar clock counts like any change; it ticks
/// once a minute, which at worst adds one quiet period.
struct ScreenSettleDetector: Sendable {
	struct Configuration: Equatable, Sendable {
		/// How long the screen must hold still to count as settled. UIKit's standard transitions
		/// run 250–350 ms but change every frame, so 300 ms with no change at all ends well after
		/// one, while staying shorter than the gaps of a caret blink (which it ignores anyway).
		var quietPeriod: Duration = .milliseconds(300)
		/// How long to keep looking for a first change before calling the screen unchanged. A warm
		/// app starts responding within a poll or two; 600 ms also covers a cold one (measured:
		/// 400 ms for the first tap into Settings after launch).
		var responseGrace: Duration = .milliseconds(600)
		/// The longest wait: an app launch takes 1–2 s, so 3 s covers it without stalling the model
		/// behind a spinner.
		var timeout: Duration = .seconds(3)
		/// In `ScreenFingerprint` units (sixteenths of a cell's mean byte sum).
		var cellTolerance: UInt32 = 16
		var ignoredCells = 4
	}

	enum Decision: Equatable, Sendable {
		case waiting
		case finished(ScreenSettleResult)
	}

	let configuration: Configuration
	private var reference: ScreenFingerprint?
	private var lastChange: Duration = .zero
	private(set) var hasChanged = false

	/// `baseline` is the screen before the action, when it was caught; without one, the first
	/// fingerprint observed is the reference and only changes after it count.
	init(baseline: ScreenFingerprint?, configuration: Configuration = Configuration()) {
		self.configuration = configuration
		reference = baseline
	}

	/// Takes the fingerprint seen `elapsed` after the action ended (non-decreasing between calls).
	mutating func observe(_ fingerprint: ScreenFingerprint, at elapsed: Duration) -> Decision {
		if let reference {
			if differs(fingerprint, from: reference) {
				self.reference = fingerprint
				lastChange = elapsed
				hasChanged = true
			}
		}
		else {
			reference = fingerprint
			lastChange = elapsed
		}

		let quiet = elapsed - lastChange
		if hasChanged, quiet >= configuration.quietPeriod {
			return .finished(.settled(after: elapsed))
		}
		if !hasChanged, elapsed >= configuration.responseGrace, quiet >= configuration.quietPeriod {
			return .finished(.unchanged(after: elapsed))
		}
		if elapsed >= configuration.timeout {
			return .finished(hasChanged ? .stillChanging(after: elapsed) : .unchanged(after: elapsed))
		}
		return .waiting
	}

	private func differs(_ fingerprint: ScreenFingerprint, from reference: ScreenFingerprint) -> Bool {
		fingerprint.changedCells(comparedTo: reference, tolerance: configuration.cellTolerance) > configuration.ignoredCells
	}
}
