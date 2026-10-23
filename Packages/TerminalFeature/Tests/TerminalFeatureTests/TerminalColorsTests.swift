import AppKit
import Foundation
import SwiftTerm
import Testing

@testable import TerminalFeature

@MainActor
@Suite("Terminal colors")
struct TerminalColorsTests {
	private func makePane() -> ClaudeAwareTerminalView {
		ClaudeAwareTerminalView(
			repositoryPath: "/tmp/repo",
			sessionId: UUID(),
			onStatusChange: { _, _, _ in },
			onNotification: { _, _ in }
		)
	}

	@Test func appliesTheThemesCaretAndSelection() {
		let pane = makePane()
		let foreground = NSColor(srgbRed: 0.9, green: 0.9, blue: 0.8, alpha: 1)

		pane.apply(TerminalColors(
			foreground: foreground,
			background: .black,
			cursor: .systemPink,
			selection: .darkGray
		))

		#expect(pane.nativeForegroundColor == foreground)
		#expect(pane.nativeBackgroundColor == .black)
		#expect(pane.caretColor == .systemPink)
		#expect(pane.selectedTextBackgroundColor == .darkGray)
		// SwiftTerm replaces the text of every selected cell with this color, black by default:
		// unreadable on the dark selections most profiles ship.
		#expect(pane.selectedTextForegroundColor == foreground)
	}

	/// A theme with no selection color keeps SwiftTerm's own pair, which go together.
	@Test func withoutASelectionColorSwiftTermsSelectionStays() {
		let pane = makePane()
		let background = pane.selectedTextBackgroundColor
		let foreground = pane.selectedTextForegroundColor
		let caret = pane.caretColor

		pane.apply(TerminalColors(foreground: .white, background: .black))

		#expect(pane.selectedTextBackgroundColor == background)
		#expect(pane.selectedTextForegroundColor == foreground)
		#expect(pane.caretColor == caret)
	}
}
