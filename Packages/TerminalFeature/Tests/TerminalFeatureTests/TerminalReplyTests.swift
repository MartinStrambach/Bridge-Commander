import Testing

@testable import TerminalFeature

struct TerminalReplyTests {
	private func matches(_ text: String) -> Bool {
		TerminalReply.matches(Array(text.utf8)[...])
	}

	/// SwiftTerm writes these into the pane that loses or gains focus when the app switches
	/// repositories, on the same path as a keystroke.
	@Test func recognisesBothFocusReports() {
		#expect(matches("\u{1B}[I"))
		#expect(matches("\u{1B}[O"))
	}

	@Test func recognisesTheEightBitForm() {
		#expect(TerminalReply.matches([0x9B, 0x49][...]))
		#expect(TerminalReply.matches([0x9B, 0x4F][...]))
		#expect(TerminalReply.matches([0x9B] + Array("6;32;16t".utf8)[...]))
	}

	/// Claude Code asks for the cell size on every focus change; this is SwiftTerm's answer, captured
	/// from a pane that was reported as typed into when the user switched tabs.
	@Test func recognisesTheCellSizeReply() {
		#expect(TerminalReply.matches([0x1B, 0x5B, 0x36, 0x3B, 0x33, 0x32, 0x3B, 0x31, 0x36, 0x74][...]))
	}

	@Test func recognisesOtherQueryReplies() {
		#expect(matches("\u{1B}[4;800;1200t")) // window size in pixels
		#expect(matches("\u{1B}[8;50;200t")) // text area in cells
		#expect(matches("\u{1B}[?62;22c")) // primary device attributes
		#expect(matches("\u{1B}[>0;276;0c")) // secondary device attributes
		#expect(matches("\u{1B}[0n")) // device status
		#expect(matches("\u{1B}[?997;1n")) // color scheme
		#expect(matches("\u{1B}[?2004;1$y")) // DEC private mode
		#expect(matches("\u{1B}[4;2$y")) // ANSI mode
		#expect(matches("\u{1B}[?1u")) // kitty keyboard flags
		#expect(matches("\u{1B}]11;rgb:1e1e/1e1e/1e1e\u{1B}\\")) // background color, ST
		#expect(matches("\u{1B}]10;rgb:ffff/ffff/ffff\u{07}")) // foreground color, BEL
		#expect(matches("\u{1B}P>|SwiftTerm\u{1B}\\")) // XTVERSION
	}

	@Test func rejectsOrdinaryKeystrokes() {
		#expect(!matches("I"))
		#expect(!matches("O"))
		#expect(!matches("t"))
		#expect(!matches("\r"))
		#expect(!TerminalReply.matches([][...]))
	}

	@Test func rejectsKeysThatAreEscapeSequences() {
		#expect(!matches("\u{1B}[A")) // up arrow
		#expect(!matches("\u{1B}[1;3D")) // Option+left
		#expect(!matches("\u{1B}[3~")) // forward delete
		#expect(!matches("\u{1B}[Z")) // Shift+Tab
		#expect(!matches("\u{1B}[97;5u")) // kitty Ctrl+A
		#expect(!matches("\u{1B}[13u")) // kitty Enter
		#expect(!matches("\u{1B}[1;2R")) // Shift+F3, the same shape as a cursor-position report
		#expect(!matches("\u{1B}[<0;10;5M")) // SGR mouse press
		#expect(!matches("\u{1B}[200~paste\u{1B}[201~")) // bracketed paste
	}

	/// Option+] and Option+⇧P send the bare introducer of an OSC or DCS reply.
	@Test func rejectsABareStringIntroducer() {
		#expect(!matches("\u{1B}]"))
		#expect(!matches("\u{1B}P"))
		#expect(!matches("\u{1B}]\u{07}"))
		#expect(!matches("\u{1B}]\u{1B}\\"))
	}

	@Test func rejectsOtherEscapeSequencesEndingInTheSameLetter() {
		// Insert Line and the cursor-position query both end in a letter a focus report uses.
		#expect(!matches("\u{1B}[2I"))
		#expect(!matches("\u{1B}[?1004O"))
	}
}
