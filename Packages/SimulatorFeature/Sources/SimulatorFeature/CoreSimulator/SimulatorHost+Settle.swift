import Foundation
import IOSurface

extension SimulatorHost {
	/// How often the framebuffer is sampled while waiting: every couple of frames at 60 Hz, fine
	/// enough to time a settle to within one poll, while a fingerprint (~1 ms) leaves the CPU alone.
	static let settlePollInterval = Duration.milliseconds(40)

	/// The screen now, to hand to `waitForScreenToSettle` after an action so that a change already
	/// under way when the action returns still counts as its effect. Nil if it cannot be read.
	func screenFingerprint(device: SimulatorDevice) -> ScreenFingerprint? {
		guard
			let screen = try? mainScreen(udid: device.id),
			let surface = ObjCRuntime.object(screen, "framebufferSurface")
		else {
			return nil
		}
		return ScreenFingerprint.sample(unsafeDowncast(surface, to: IOSurfaceRef.self))
	}

	/// Watches the screen until it stops changing (see `ScreenSettleDetector` for the rules), so a
	/// tool can report an action done once its result is on screen rather than when its events
	/// were sent. `drain()` still runs first: it is what gets the events delivered.
	func waitForScreenToSettle(
		device: SimulatorDevice,
		timeout: Duration = .seconds(3),
		quietPeriod: Duration = .milliseconds(300),
		baseline: ScreenFingerprint? = nil
	) async -> ScreenSettleResult {
		guard let screen = try? mainScreen(udid: device.id) else {
			return .unavailable
		}
		var configuration = ScreenSettleDetector.Configuration()
		configuration.timeout = timeout
		configuration.quietPeriod = quietPeriod
		var detector = ScreenSettleDetector(baseline: baseline, configuration: configuration)

		let clock = ContinuousClock()
		let start = clock.now
		var surface: AnyObject?
		var poll = 0
		while !Task.isCancelled {
			// Asking for the surface is a round trip to CoreSimulator that takes up to 100 ms while
			// the simulator is busy animating, so it is reused between polls — but asked for again
			// every few, since CoreSimulator can replace it (its surfaces-changed callback) and a
			// stale one would look perfectly still.
			if poll % 8 == 0 || surface == nil {
				surface = ObjCRuntime.object(screen, "framebufferSurface")
			}
			poll += 1
			guard let surface, let fingerprint = ScreenFingerprint.sample(unsafeDowncast(surface, to: IOSurfaceRef.self)) else {
				return .unavailable
			}
			if case let .finished(result) = detector.observe(fingerprint, at: clock.now - start) {
				return result
			}
			try? await Task.sleep(for: Self.settlePollInterval)
		}
		return .unavailable
	}
}
