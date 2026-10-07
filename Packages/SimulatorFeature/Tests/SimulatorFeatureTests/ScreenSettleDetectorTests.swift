import Foundation
import Testing
@testable import SimulatorFeature

struct ScreenSettleDetectorTests {
	/// A 10×10 grid, every cell `value`, with `changed` cells (from the first) set to `other`.
	private static func screen(_ value: UInt32 = 1000, changed: Int = 0, to other: UInt32 = 5000) -> ScreenFingerprint {
		var cells = [UInt32](repeating: value, count: 100)
		for index in 0..<changed {
			cells[index] = other
		}
		return ScreenFingerprint(columns: 10, rows: 10, cells: cells)
	}

	private static func ms(_ value: Int) -> Duration {
		.milliseconds(value)
	}

	/// Feeds `frames` (fingerprint, milliseconds) until the detector decides.
	private static func run(
		baseline: ScreenFingerprint?,
		_ frames: [(ScreenFingerprint, Int)],
		configuration: ScreenSettleDetector.Configuration = .init()
	) -> ScreenSettleResult? {
		var detector = ScreenSettleDetector(baseline: baseline, configuration: configuration)
		for (fingerprint, time) in frames {
			if case let .finished(result) = detector.observe(fingerprint, at: ms(time)) {
				return result
			}
		}
		return nil
	}

	/// The same fingerprint every 40 ms from `start` up to and including `end`.
	private static func still(_ fingerprint: ScreenFingerprint, from start: Int, through end: Int) -> [(ScreenFingerprint, Int)] {
		stride(from: start, through: end, by: 40).map { (fingerprint, $0) }
	}

	@Test
	func aStillScreenIsUnchangedOnceTheResponseGraceHasPassed() {
		let frames = Self.still(Self.screen(), from: 0, through: 2000)
		#expect(Self.run(baseline: Self.screen(), frames) == .unchanged(after: Self.ms(600)))
	}

	@Test
	func withoutABaselineTheFirstFrameIsTheReference() {
		let frames = Self.still(Self.screen(changed: 50), from: 0, through: 2000)
		#expect(Self.run(baseline: nil, frames) == .unchanged(after: Self.ms(600)))
	}

	@Test
	func aChangeAlreadyUnderWaySettlesAQuietPeriodAfterItStops() {
		// The action left the screen different from the baseline; then it held still.
		let frames = Self.still(Self.screen(changed: 50), from: 0, through: 2000)
		#expect(Self.run(baseline: Self.screen(), frames) == .settled(after: Self.ms(320)))
	}

	@Test
	func anAnimationSettlesAQuietPeriodAfterItsLastFrame() {
		// Frames keep changing until 400 ms, then hold.
		let moving = (0...10).map { step in (Self.screen(UInt32(1000 + step * 100)), step * 40) }
		let frames = moving + Self.still(Self.screen(2000), from: 440, through: 2000)
		#expect(Self.run(baseline: Self.screen(), frames) == .settled(after: Self.ms(720)))
	}

	@Test
	func aLateResponseWithinTheGraceStillCounts() {
		let frames = Self.still(Self.screen(), from: 0, through: 400) + Self.still(Self.screen(changed: 30), from: 440, through: 2000)
		#expect(Self.run(baseline: Self.screen(), frames) == .settled(after: Self.ms(760)))
	}

	@Test
	func aScreenThatNeverStopsChangingTimesOut() {
		let frames = (0...100).map { step in (Self.screen(UInt32(1000 + step % 2 * 500)), step * 40) }
		#expect(Self.run(baseline: Self.screen(), frames) == .stillChanging(after: Self.ms(3000)))
	}

	@Test
	func aShorterTimeoutAndQuietPeriodAreHonoured() {
		var configuration = ScreenSettleDetector.Configuration()
		configuration.timeout = .seconds(1)
		configuration.quietPeriod = .milliseconds(100)
		let flicker = (0...50).map { step in (Self.screen(UInt32(1000 + step % 2 * 500)), step * 40) }
		#expect(Self.run(baseline: Self.screen(), flicker, configuration: configuration) == .stillChanging(after: Self.ms(1000)))

		let settle = [(Self.screen(changed: 20), 0)] + Self.still(Self.screen(changed: 20), from: 40, through: 400)
		#expect(Self.run(baseline: Self.screen(), settle, configuration: configuration) == .settled(after: Self.ms(120)))
	}

	@Test
	func aBlinkingCaretIsIgnored() {
		// Four cells toggling forever, as a caret does: neither a change nor something to wait out.
		let frames = (0...100).map { step in (Self.screen(changed: step / 5 % 2 == 0 ? 0 : 4), step * 40) }
		#expect(Self.run(baseline: Self.screen(), frames) == .unchanged(after: Self.ms(600)))
	}

	@Test
	func aCaretBlinkingAfterARealChangeDoesNotHoldTheWaitOpen() {
		let typed = Self.screen(changed: 30)
		var blinking = typed.cells
		blinking[90...93] = [9000, 9000, 9000, 9000]
		let caretOff = ScreenFingerprint(columns: 10, rows: 10, cells: blinking)
		let frames = (0...100).map { step in (step / 3 % 2 == 0 ? typed : caretOff, step * 40) }
		#expect(Self.run(baseline: Self.screen(), frames) == .settled(after: Self.ms(320)))
	}

	@Test
	func changesWithinTheCellToleranceAreNoise() {
		let frames = (0...60).map { step in (Self.screen(UInt32(1000 + step % 2 * 16)), step * 40) }
		#expect(Self.run(baseline: Self.screen(), frames) == .unchanged(after: Self.ms(600)))
	}

	@Test
	func aSlowFadeAddsUpToAChange() {
		// 10 units a frame never exceeds the tolerance frame to frame, but does against the reference.
		let fade = (0...20).map { step in (Self.screen(UInt32(1000 + step * 10)), step * 40) }
		let frames = fade + Self.still(Self.screen(1200), from: 840, through: 3000)
		// The last step to pass the tolerance lands at 800 ms.
		#expect(Self.run(baseline: Self.screen(), frames) == .settled(after: Self.ms(1120)))
	}

	@Test
	func aReplacedSurfaceOfAnotherSizeIsAChange() {
		let rotated = ScreenFingerprint(columns: 20, rows: 5, cells: [UInt32](repeating: 1000, count: 100))
		#expect(rotated.changedCells(comparedTo: Self.screen(), tolerance: 16) == 100)
		#expect(Self.run(baseline: Self.screen(), Self.still(rotated, from: 0, through: 1000)) == .settled(after: Self.ms(320)))
	}

	@Test
	func summariesNameTheOutcomeAndTime() {
		#expect(ScreenSettleResult.settled(after: .milliseconds(640)).summary == "Screen settled after 640 ms.")
		#expect(ScreenSettleResult.unchanged(after: .milliseconds(600)).summary.hasPrefix("No change on screen within 600 ms"))
		#expect(ScreenSettleResult.stillChanging(after: .seconds(3)).summary.hasPrefix("Screen still changing after 3000 ms"))
	}
}

struct ScreenFingerprintTests {
	/// A BGRA buffer of `width`×`height`, every pixel `pixel`, with `padding` spare bytes a row.
	private static func buffer(width: Int, height: Int, padding: Int = 0, pixel: [UInt8] = [10, 20, 30, 255]) -> (bytes: [UInt8], bytesPerRow: Int) {
		let bytesPerRow = width * 4 + padding
		var bytes = [UInt8](repeating: 0xEE, count: bytesPerRow * height)
		for y in 0..<height {
			for x in 0..<width {
				bytes.replaceSubrange(y * bytesPerRow + x * 4 ..< y * bytesPerRow + x * 4 + 4, with: pixel)
			}
		}
		return (bytes, bytesPerRow)
	}

	private static func fingerprint(_ bytes: [UInt8], width: Int, height: Int, bytesPerRow: Int) -> ScreenFingerprint {
		bytes.withUnsafeBytes { raw in
			ScreenFingerprint.sample(raw.baseAddress!, width: width, height: height, bytesPerRow: bytesPerRow)
		}
	}

	@Test
	func aUniformScreenGivesEveryCellTheMeanByteSum() {
		let (bytes, bytesPerRow) = Self.buffer(width: 240, height: 480)
		let fingerprint = Self.fingerprint(bytes, width: 240, height: 480, bytesPerRow: bytesPerRow)
		#expect(fingerprint.columns == 5)
		#expect(fingerprint.rows == 10)
		// (10 + 20 + 30 + 255) in sixteenths.
		#expect(fingerprint.cells.allSatisfy { $0 == 315 * 16 })
	}

	@Test
	func rowPaddingIsNotSampled() {
		let (bytes, bytesPerRow) = Self.buffer(width: 240, height: 480, padding: 64)
		let fingerprint = Self.fingerprint(bytes, width: 240, height: 480, bytesPerRow: bytesPerRow)
		#expect(fingerprint.cells.allSatisfy { $0 == 315 * 16 })
	}

	@Test
	func aCaretSizedChangeMovesOnlyTheCellsUnderIt() {
		let width = 1206
		let height = 2622
		var (bytes, bytesPerRow) = Self.buffer(width: width, height: height, pixel: [255, 255, 255, 255])
		let before = Self.fingerprint(bytes, width: width, height: height, bytesPerRow: bytesPerRow)

		// A 2-point caret at 3×: 6 pixels wide, 66 tall, inside one column of cells.
		for y in 1000..<1066 {
			for x in 200..<206 {
				bytes.replaceSubrange(y * bytesPerRow + x * 4 ..< y * bytesPerRow + x * 4 + 4, with: [255, 122, 10, 255])
			}
		}
		let after = Self.fingerprint(bytes, width: width, height: height, bytesPerRow: bytesPerRow)
		let changed = after.changedCells(comparedTo: before, tolerance: ScreenSettleDetector.Configuration().cellTolerance)
		#expect(changed >= 1)
		#expect(changed <= ScreenSettleDetector.Configuration().ignoredCells)
	}

	@Test
	func aToggleSizedChangeIsMoreThanNoise() {
		let width = 1206
		let height = 2622
		var (bytes, bytesPerRow) = Self.buffer(width: width, height: height, pixel: [30, 30, 30, 255])
		let before = Self.fingerprint(bytes, width: width, height: height, bytesPerRow: bytesPerRow)

		// A switch's track turning green: 51×31 points at 3×.
		for y in 1500..<1593 {
			for x in 900..<1053 {
				bytes.replaceSubrange(y * bytesPerRow + x * 4 ..< y * bytesPerRow + x * 4 + 4, with: [89, 199, 52, 255])
			}
		}
		let after = Self.fingerprint(bytes, width: width, height: height, bytesPerRow: bytesPerRow)
		let changed = after.changedCells(comparedTo: before, tolerance: ScreenSettleDetector.Configuration().cellTolerance)
		#expect(changed > ScreenSettleDetector.Configuration().ignoredCells)
	}
}
