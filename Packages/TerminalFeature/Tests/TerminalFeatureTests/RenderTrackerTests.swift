import Testing

@testable import TerminalFeature

struct RenderTrackerTests {
	/// The input box Claude draws when it is waiting.
	private static let promptFrame = Array("\r\u{1B}[1B\u{1B}[39m❯\u{A0}".utf8)

	@Test func remembersThatTheRenderDrewThePrompt() {
		var tracker = RenderTracker()
		tracker.received(Self.promptFrame)
		#expect(tracker.drewPrompt)
	}

	@Test func aRenderThatDrewNoPromptIsNotRemembered() {
		var tracker = RenderTracker()
		tracker.received(Array("✻ Thinking… (12s)".utf8))
		#expect(!tracker.drewPrompt)
	}

	@Test func laterBurstsOfTheSameRenderKeepWhatItDrew() {
		var tracker = RenderTracker()
		tracker.received(Self.promptFrame)
		tracker.received(Array("? for shortcuts".utf8))
		#expect(tracker.drewPrompt)
	}

	@Test func aBurstAfterAJudgementStartsAFreshRender() {
		// Once a frame has been judged, what it drew says nothing about the next one.
		var tracker = RenderTracker()
		tracker.received(Self.promptFrame)
		tracker.markJudged()
		tracker.received(Array("✻ Working…".utf8))
		#expect(!tracker.drewPrompt)
	}
}
