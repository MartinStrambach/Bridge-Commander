import SwiftTerm

/// The environment each pane's shell starts with.
enum TerminalEnvironment {
	/// SwiftTerm's defaults. Claude Code needs nothing more to report its status: it asks the
	/// terminal (`OSC 7501 ; ?`) rather than reading the environment, and SwiftTerm answers.
	static var variables: [String] {
		Terminal.getEnvironmentVariables(termName: "xterm-256color")
	}
}
