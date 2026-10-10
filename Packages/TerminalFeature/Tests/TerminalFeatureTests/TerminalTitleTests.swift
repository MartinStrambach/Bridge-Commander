import AppKit
import Foundation
import SwiftTerm
import Testing

@testable import TerminalFeature

@Suite("Terminal tab title")
struct TerminalTitleTests {
	@Test("a tab is named by its run title, then its program's title, then its number")
	func tabTitleFallsBack() {
		var session = TerminalSession(repositoryPath: "/r", tabIndex: 3)
		#expect(session.tabTitle == "Terminal 3")

		session.title = "Fix the login bug"
		#expect(session.tabTitle == "Fix the login bug")

		var run = TerminalSession(repositoryPath: "/r", runTitle: "MyApp", tabIndex: 2)
		run.title = "xcodebuild"
		#expect(run.tabTitle == "MyApp")
	}

	@MainActor
	@Test("the pane passes on the titles its program sets (OSC 0 and 2), cleaned for display")
	func paneForwardsTitles() async {
		let received = Titles()
		let delegate = TerminalProcessDelegate(
			onFailed: { _ in },
			onTitleChange: { title in MainActor.assumeIsolated { received.items.append(title) } }
		)
		let view = ClaudeAwareTerminalView(
			repositoryPath: "/tmp/repo",
			sessionId: UUID(),
			onStatusChange: { _, _, _ in },
			onNotification: { _, _ in }
		)
		view.frame = NSRect(x: 0, y: 0, width: 600, height: 300)
		view.processDelegate = delegate

		view.feed(text: "\u{1B}]0;Fix the login bug\u{07}")
		// A text direction override would make the tab read differently from what was sent.
		view.feed(text: "\u{1B}]2;  Review\u{202E} PR  \u{1B}\\")
		view.feed(text: "\u{1B}]2;\u{07}")

		let expected: [String?] = ["Fix the login bug", "Review PR", nil]
		let clock = ContinuousClock()
		let deadline = clock.now + .seconds(5)
		while received.items != expected, clock.now < deadline {
			try? await Task.sleep(for: .milliseconds(20))
		}

		#expect(received.items == expected)
	}
}

@MainActor
private final class Titles {
	var items: [String?] = []
}
