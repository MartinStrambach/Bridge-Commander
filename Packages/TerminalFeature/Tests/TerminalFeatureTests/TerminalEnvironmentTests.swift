import Testing

@testable import TerminalFeature

struct TerminalEnvironmentTests {
	@Test func claimsConEmuSoClaudeReportsProgress() {
		#expect(TerminalEnvironment.variables().contains("ConEmuANSI=ON"))
	}

	@Test func keepsSwiftTermsDefaults() {
		let variables = TerminalEnvironment.variables()
		#expect(variables.contains("TERM=xterm-256color"))
		#expect(variables.contains("COLORTERM=truecolor"))
	}
}
