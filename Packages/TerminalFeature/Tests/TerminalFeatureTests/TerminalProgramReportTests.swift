import Foundation
import SwiftTerm
import Testing

@testable import TerminalFeature

/// Records are built the way a pane gets them: OSC 7501 reports fed through SwiftTerm's parser,
/// since `TerminalProgramStatus` has no public initializer.
struct TerminalProgramReportTests {
	private final class Delegate: TerminalDelegate {
		func send(source: Terminal, data: ArraySlice<UInt8>) {}
	}

	private static func status(after reports: [String]) -> TerminalProgramReport? {
		let delegate = Delegate()
		let terminal = Terminal(delegate: delegate)
		for report in reports {
			terminal.feed(text: "\u{1B}]7501;\(report)\u{1B}\\")
		}
		return TerminalProgramReport(records: terminal.programStatusRecords)
	}

	@Test func readsTheRootRecord() {
		let status = Self.status(after: ["state=working:app=claude-code"])
		#expect(status == TerminalProgramReport(program: "claude-code", state: .working, message: nil))
	}

	@Test func readsAnyProgram() {
		// "Allow write?"
		let status = Self.status(after: ["state=blocked:app=codex:kind=permission:msg=QWxsb3cgd3JpdGU/"])
		#expect(status == TerminalProgramReport(program: "codex", state: .blocked(.permission), message: "Allow write?"))
	}

	@Test func readsAProgramThatGivesNoName() {
		let status = Self.status(after: ["state=done"])
		#expect(status?.state == .done)
		#expect(status?.program == nil)
		#expect(status?.displayName == "A program")
	}

	@Test func takesTheTitleWhenThereIsNoMessage() {
		// "Build"
		let status = Self.status(after: ["state=done:app=make:title=QnVpbGQ="])
		#expect(status?.message == "Build")
	}

	@Test func takesTheTitleWhenTheMessageIsBlank() {
		// An empty message, then " " ("IA=="): neither leaves anything to show, the title does.
		#expect(Self.status(after: ["state=done:app=make:msg=:title=QnVpbGQ="])?.message == "Build")
		#expect(Self.status(after: ["state=done:app=make:msg=IA==:title=QnVpbGQ="])?.message == "Build")
	}

	@Test func readsTheLatestReport() {
		let status = Self.status(after: [
			"state=working:app=claude-code",
			"state=blocked:app=claude-code:kind=permission",
		])
		#expect(status?.state == .blocked(.permission))
	}

	@Test(arguments: [
		("state=blocked:kind=question", TerminalProgramReport.State.blocked(.question)),
		("state=blocked:kind=auth", .blocked(.signIn)),
		("state=blocked", .blocked(nil)),
		("state=idle", .idle),
		("state=error", .error),
	])
	func readsTheState(report: String, state: TerminalProgramReport.State) {
		#expect(Self.status(after: [report])?.state == state)
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
		#expect(TerminalProgramReport(program: "claude-code", state: .done, message: nil).displayName == "Claude")
		#expect(TerminalProgramReport(program: "codex", state: .done, message: nil).displayName == "codex")
	}

	@Test(arguments: [
		(TerminalProgramReport.State.blocked(.permission), "Claude needs your permission."),
		(.blocked(.question), "Claude has a question."),
		(.blocked(.signIn), "Claude needs you to sign in."),
		(.blocked(nil), "Claude needs your input."),
		(.done, "Claude is done."),
		(.idle, "Claude is waiting for your input."),
		(.error, "Claude ran into an error."),
	])
	func saysWhatTheProgramWaitsFor(state: TerminalProgramReport.State, body: String) {
		#expect(TerminalProgramReport(program: "claude-code", state: state, message: nil).notificationBody == body)
	}

	@Test func addsTheProgramsMessage() {
		let report = TerminalProgramReport(program: "codex", state: .blocked(.permission), message: "Allow write?")
		#expect(report.notificationBody == "codex needs your permission: Allow write?")
		#expect(
			TerminalProgramReport(program: nil, state: .done, message: nil).notificationBody == "A program is done."
		)
	}

	@Test func dropsInvisibleFormattingCharacters() {
		// A right-to-left override would make the rest of a notification read backwards.
		#expect(TerminalProgramReport.displayText("Hi\u{202E}there\u{200B}") == "Hithere")
	}

	@Test func dropsTextThatIsOnlyInvisible() {
		#expect(TerminalProgramReport.displayText("\u{200B} \u{2066}") == nil)
		#expect(TerminalProgramReport.displayText(nil) == nil)
	}

	@Test func turnsLineAndParagraphSeparatorsIntoSpaces() {
		#expect(TerminalProgramReport.displayText("one\u{2028}two\u{2029}three") == "one two three")
	}

	@Test func keepsAMessageThatJustFits() {
		let text = String(repeating: "a", count: 10)
		#expect(TerminalProgramReport.displayText(text, maxLength: 10) == text)
	}

	@Test func shortensALongMessage() {
		let text = TerminalProgramReport.displayText(String(repeating: "a", count: 50), maxLength: 10)
		#expect(text == String(repeating: "a", count: 9) + "…")
	}
}
