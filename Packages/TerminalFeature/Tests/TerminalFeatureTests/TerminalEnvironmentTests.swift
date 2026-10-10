import Testing

@testable import TerminalFeature

struct TerminalEnvironmentTests {
	@Test func keepsSwiftTermsDefaults() {
		#expect(TerminalEnvironment.variables.contains("TERM=xterm-256color"))
		#expect(TerminalEnvironment.variables.contains("COLORTERM=truecolor"))
	}

	@Test func claimsNoOtherTerminal() {
		// Claiming ConEmu once made Claude Code send OSC 9;4 progress. Its status now comes over
		// OSC 7501, which it asks the terminal about instead.
		#expect(!TerminalEnvironment.variables.contains("ConEmuANSI=ON"))
	}
}
