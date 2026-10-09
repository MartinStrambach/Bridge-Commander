import Foundation
import SwiftTerm
import Testing

@testable import TerminalFeature

/// Records are built the way a pane gets them: OSC 7501 reports fed through SwiftTerm's parser,
/// since `TerminalProgramStatus` has no public initializer.
struct ProgramStatusReportTests {
	private final class Delegate: TerminalDelegate {
		func send(source: Terminal, data: ArraySlice<UInt8>) {}
	}

	private static func status(after reports: [String]) -> ProgramStatusReport? {
		let delegate = Delegate()
		let terminal = Terminal(delegate: delegate)
		for report in reports {
			terminal.feed(text: "\u{1B}]7501;\(report)\u{1B}\\")
		}
		return ProgramStatusReport(records: terminal.programStatusRecords)
	}

	@Test func readsTheRootRecord() {
		let status = Self.status(after: ["state=working:app=claude-code"])
		#expect(status?.state == .working)
		#expect(status?.report == TerminalProgramReport(program: "claude-code", message: nil))
	}

	@Test func readsAnyProgram() {
		// "Allow write?"
		let status = Self.status(after: ["state=blocked:app=codex:kind=permission:msg=QWxsb3cgd3JpdGU/"])
		#expect(status?.state == .blocked)
		#expect(status?.report == TerminalProgramReport(program: "codex", message: "Allow write?"))
	}

	@Test func readsAProgramThatGivesNoName() {
		let status = Self.status(after: ["state=done"])
		#expect(status?.state == .done)
		#expect(status?.report.program == nil)
		#expect(status?.report.displayName == "A program")
	}

	@Test func takesTheTitleWhenThereIsNoMessage() {
		// "Build"
		let status = Self.status(after: ["state=done:app=make:title=QnVpbGQ="])
		#expect(status?.report.message == "Build")
	}

	@Test func readsTheLatestReport() {
		let status = Self.status(after: [
			"state=working:app=claude-code",
			"state=blocked:app=claude-code:kind=permission",
		])
		#expect(status?.state == .blocked)
	}

	@Test func aSubtaskStillWorkingDoesNotMakeTheProgramWork() {
		// What Claude sends when a turn ends with a background task still running.
		let status = Self.status(after: [
			"state=done:app=claude-code",
			"state=working:id=task-1",
		])
		#expect(status?.state == .done)
	}

	@Test func aSubtaskAloneIsNoReport() {
		#expect(Self.status(after: ["state=working:app=claude-code:id=task-1"]) == nil)
	}

	@Test func aClearLeavesNoReport() {
		// Claude's last word on exit.
		#expect(Self.status(after: ["state=done:app=claude-code", "state=clear"]) == nil)
	}

	// MARK: - Display

	@Test func namesClaudeAsUsersKnowIt() {
		#expect(TerminalProgramReport(program: "claude-code", message: nil).displayName == "Claude")
		#expect(TerminalProgramReport(program: "codex", message: nil).displayName == "codex")
	}

	@Test func dropsInvisibleFormattingCharacters() {
		// A right-to-left override would make the rest of a notification read backwards.
		#expect(TerminalProgramReport.displayText("Hi\u{202E}there\u{200B}") == "Hithere")
	}

	@Test func dropsTextThatIsOnlyInvisible() {
		#expect(TerminalProgramReport.displayText("\u{200B} \u{2066}") == nil)
		#expect(TerminalProgramReport.displayText(nil) == nil)
	}

	@Test func shortensALongMessage() {
		let text = TerminalProgramReport.displayText(String(repeating: "a", count: 50), maxLength: 10)
		#expect(text == String(repeating: "a", count: 9) + "…")
	}
}
