import Foundation
import Testing

@testable import TerminalFeature

/// A screen written down row by row. A `nil` row has nothing on it, which is how a real pane reports
/// the untouched rows below the frame Claude drew.
@MainActor
private final class FakeScreen: PromptScreen {
	var rows: [String?] = []
	var cursorRow = 0
	var isShowingLiveScreen = true
	var isClaudeInForeground: Bool? = true

	var rowCount: Int {
		rows.count
	}

	func row(_ row: Int, drawsScalar scalar: UInt32, withinColumns columns: Int) -> Bool? {
		guard
			rows.indices.contains(row),
			let text = rows[row]
		else {
			return nil
		}

		return text.unicodeScalars.prefix(columns).contains { $0.value == scalar }
	}
}

/// Collects what the detector reported, in order.
@MainActor
private final class Reported {
	var statuses: [TerminalSessionStatus] = []
}

@MainActor
struct ClaudeStatusDetectorTests {
	/// Claude's input box while it waits: the cursor sits in it, just after the prompt glyph.
	private static let inputBox = ["╭──────────╮", "│ ❯ ", "╰──────────╯"]

	/// An idle threshold no test will reach, so the only checks that run are the ones a test asks
	/// for. The detector re-arms its debounce as it goes, and a check firing behind a test's back
	/// would make the recorded statuses depend on timing.
	private static let neverFires: TimeInterval = 3600

	private func makeDetector(
		screen: FakeScreen,
		reported: Reported
	) -> ClaudeStatusDetector {
		ClaudeStatusDetector(
			label: "test",
			screen: screen,
			idleThreshold: Self.neverFires,
			onStatusChange: { reported.statuses.append($0) }
		)
	}

	// MARK: - Finding the prompt

	@Test func waitsWhenTheCursorSitsAtThePrompt() {
		let screen = FakeScreen()
		screen.rows = ["ran some tests"] + Self.inputBox
		screen.cursorRow = 2

		let reported = Reported()
		let detector = makeDetector(screen: screen, reported: reported)
		detector.checkIdleState()

		#expect(reported.statuses == [.waitingForInput])
	}

	@Test func waitsWhenAStaleFrameTailSitsBelowTheCursor() {
		// What a resize leaves behind: the new frame is drawn at the top and the tail of the
		// previous one is still on the rows underneath. A walk up from the bottom of the screen
		// spends its whole budget on that tail and never reaches the box.
		let screen = FakeScreen()
		screen.rows = ["│ ❯ "] + Array(repeating: "leftover output", count: 20)
		screen.cursorRow = 0

		let reported = Reported()
		let detector = makeDetector(screen: screen, reported: reported)
		detector.checkIdleState()

		#expect(reported.statuses == [.waitingForInput])
	}

	@Test func waitsWhenADialogArrowIsOnScreenAwayFromTheCursor() {
		// Claude parks the cursor outside the frame while a permission dialog is up, so the arrow
		// marking the selected option has to be found by the walk.
		let screen = FakeScreen()
		screen.rows = ["Allow this edit?", "❯ 1. Yes", "  2. No", nil]
		screen.cursorRow = 3

		let reported = Reported()
		let detector = makeDetector(screen: screen, reported: reported)
		detector.checkIdleState()

		#expect(reported.statuses == [.waitingForInput])
	}

	@Test func ignoresThePromptGlyphWhenClaudeIsNotInTheForeground() {
		// A shell theme drawing `❯` is not Claude waiting for anything.
		let screen = FakeScreen()
		screen.rows = ["❯ "]
		screen.isClaudeInForeground = false

		let reported = Reported()
		let detector = makeDetector(screen: screen, reported: reported)
		detector.checkIdleState()

		#expect(reported.statuses.isEmpty, "a pane starts active and should have stayed there")
	}

	// MARK: - Scrollback

	@Test func judgesTheLastFrameDrawnWhileTheUserReadsScrollback() {
		let screen = FakeScreen()
		screen.rows = ["a page of history", "with no prompt on it"]
		screen.isShowingLiveScreen = false

		let reported = Reported()
		let detector = makeDetector(screen: screen, reported: reported)
		detector.outputReceived(Array("\u{1B}[39m❯\u{A0}".utf8)[...])
		detector.checkIdleState()

		#expect(reported.statuses == [.waitingForInput])
	}

	@Test func staysActiveInScrollbackWhenTheLastFrameDrewNoPrompt() {
		let screen = FakeScreen()
		screen.isShowingLiveScreen = false

		let reported = Reported()
		let detector = makeDetector(screen: screen, reported: reported)
		detector.outputReceived(Array("✻ Thinking…".utf8)[...])
		detector.checkIdleState()

		#expect(reported.statuses.isEmpty)
	}

	// MARK: - Leaving the waiting state

	@Test func holdsTheWaitingStateThroughOneScreenWithNoPrompt() {
		// The flash: switching repository resizes every pane, and a check landing mid-repaint reads
		// a screen the prompt has been cleared from.
		let screen = FakeScreen()
		screen.rows = Self.inputBox
		screen.cursorRow = 1

		let reported = Reported()
		let detector = makeDetector(screen: screen, reported: reported)
		detector.checkIdleState()
		#expect(reported.statuses == [.waitingForInput])

		screen.rows = ["repainting"]
		screen.cursorRow = 0
		detector.checkIdleState()
		#expect(reported.statuses == [.waitingForInput], "one screen without a prompt is not enough")

		detector.checkIdleState()
		#expect(reported.statuses == [.waitingForInput, .active], "a second agreeing check releases it")
	}

	@Test func aKeystrokeReleasesTheWaitingStateAtOnce() {
		let screen = FakeScreen()
		screen.rows = Self.inputBox
		screen.cursorRow = 1

		let reported = Reported()
		let detector = makeDetector(screen: screen, reported: reported)
		detector.checkIdleState()

		detector.inputSent(Array("h".utf8)[...])

		#expect(reported.statuses == [.waitingForInput, .active])
	}

	@Test func aFocusReportDoesNotReleaseTheWaitingState() {
		let screen = FakeScreen()
		screen.rows = Self.inputBox
		screen.cursorRow = 1

		let reported = Reported()
		let detector = makeDetector(screen: screen, reported: reported)
		detector.checkIdleState()

		detector.inputSent(Array("\u{1B}[O".utf8)[...])

		#expect(reported.statuses == [.waitingForInput])
	}

	@Test func outputAloneDoesNotReleaseTheWaitingState() {
		// Every child repaints when the app resizes its pane. That output is not Claude working.
		let screen = FakeScreen()
		screen.rows = Self.inputBox
		screen.cursorRow = 1

		let reported = Reported()
		let detector = makeDetector(screen: screen, reported: reported)
		detector.checkIdleState()

		detector.outputReceived(Array("a whole frame of repaint".utf8)[...])

		#expect(reported.statuses == [.waitingForInput])
	}
}
