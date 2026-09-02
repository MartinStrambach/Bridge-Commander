import Testing

@testable import TerminalFeature

struct FocusReportTests {
	/// SwiftTerm writes these into the pane that loses or gains focus when the app switches
	/// repositories, on the same path as a keystroke.
	@Test func recognisesBothFocusReports() {
		#expect(FocusReport.matches(Array("\u{1B}[I".utf8)[...]))
		#expect(FocusReport.matches(Array("\u{1B}[O".utf8)[...]))
	}

	@Test func recognisesTheEightBitForm() {
		#expect(FocusReport.matches([0x9B, 0x49][...]))
		#expect(FocusReport.matches([0x9B, 0x4F][...]))
	}

	@Test func rejectsOrdinaryKeystrokes() {
		#expect(!FocusReport.matches(Array("I".utf8)[...]))
		#expect(!FocusReport.matches(Array("O".utf8)[...]))
		#expect(!FocusReport.matches(Array("\r".utf8)[...]))
		#expect(!FocusReport.matches([][...]))
	}

	@Test func rejectsOtherEscapeSequencesEndingInTheSameLetter() {
		// Insert Line and the cursor-position query both end in a letter a focus report uses.
		#expect(!FocusReport.matches(Array("\u{1B}[2I".utf8)[...]))
		#expect(!FocusReport.matches(Array("\u{1B}[?1004O".utf8)[...]))
	}
}
