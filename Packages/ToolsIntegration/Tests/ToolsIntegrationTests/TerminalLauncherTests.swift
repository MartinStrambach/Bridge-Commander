import Foundation
import Testing
@testable import ToolsIntegration

@Suite("Terminal launcher command building")
struct TerminalLauncherTests {

	// MARK: - Shell Command

	@Test("a plain path becomes a bare cd")
	func plainPath() {
		#expect(TerminalLauncher.shellCommand(at: "/tmp/repo", command: nil) == "cd '/tmp/repo'")
	}

	@Test("a command is chained onto the cd")
	func chainedCommand() {
		#expect(
			TerminalLauncher.shellCommand(at: "/tmp/repo", command: "claude")
				== "cd '/tmp/repo' && claude"
		)
	}

	@Test("an empty command is treated as no command")
	func emptyCommand() {
		#expect(TerminalLauncher.shellCommand(at: "/tmp/repo", command: "") == "cd '/tmp/repo'")
	}

	@Test("spaces in the path stay inside the quotes")
	func pathWithSpaces() {
		#expect(
			TerminalLauncher.shellCommand(at: "/Users/me/My Repos/app", command: nil)
				== "cd '/Users/me/My Repos/app'"
		)
	}

	@Test("an apostrophe in the path is closed, escaped and reopened")
	func pathWithApostrophe() {
		#expect(
			TerminalLauncher.shellCommand(at: "/Users/me/Martin's repo", command: "claude")
				== "cd '/Users/me/Martin'\\''s repo' && claude"
		)
	}

	@Test("shell metacharacters in the path are never interpreted")
	func pathWithShellMetacharacters() {
		#expect(
			TerminalLauncher.shellCommand(at: "/tmp/$HOME `whoami` \"x\"", command: nil)
				== "cd '/tmp/$HOME `whoami` \"x\"'"
		)
	}

	// MARK: - AppleScript Literal

	@Test("a plain string is simply quoted")
	func plainLiteral() {
		#expect(TerminalLauncher.appleScriptLiteral("cd '/tmp'") == "\"cd '/tmp'\"")
	}

	@Test("double quotes are escaped so the literal cannot be closed early")
	func literalWithDoubleQuote() {
		#expect(TerminalLauncher.appleScriptLiteral("say \"hi\"") == "\"say \\\"hi\\\"\"")
	}

	@Test("backslashes are escaped before the quotes are")
	func literalWithBackslash() {
		#expect(TerminalLauncher.appleScriptLiteral("a\\b") == "\"a\\\\b\"")
		#expect(TerminalLauncher.appleScriptLiteral("a\\\"b") == "\"a\\\\\\\"b\"")
	}
}
