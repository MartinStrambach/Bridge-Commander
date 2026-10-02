import Testing

@testable import TerminalFeature

struct TerminalEnvironmentTests {
	@Test func claimsConEmuSoClaudeReportsProgress() {
		#expect(TerminalEnvironment.variables(requestingProgress: true).contains("ConEmuANSI=ON"))
	}

	@Test func leavesConEmuOutWhenProgressIsNotWanted() {
		#expect(!TerminalEnvironment.variables(requestingProgress: false).contains("ConEmuANSI=ON"))
	}

	@Test(arguments: [true, false])
	func keepsSwiftTermsDefaults(requestingProgress: Bool) {
		let variables = TerminalEnvironment.variables(requestingProgress: requestingProgress)
		#expect(variables.contains("TERM=xterm-256color"))
		#expect(variables.contains("COLORTERM=truecolor"))
	}
}
