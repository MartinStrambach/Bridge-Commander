import Testing

@testable import TerminalFeature

struct PtyForegroundProcessTests {
	@Test func nativeInstallIsClaude() {
		// The native install execs a version-named binary, so argv[0] is the only marker.
		#expect(PtyForegroundProcess.isClaude(arguments: ["claude"]))
		#expect(PtyForegroundProcess.isClaude(arguments: ["/Users/me/.local/bin/claude", "--continue"]))
	}

	@Test func npmInstallIsClaude() {
		#expect(PtyForegroundProcess.isClaude(arguments: [
			"node",
			"/usr/local/lib/node_modules/@anthropic-ai/claude-code/cli.js",
		]))
	}

	@Test func shellIsNotClaude() {
		#expect(!PtyForegroundProcess.isClaude(arguments: ["/bin/zsh", "-l"]))
		#expect(!PtyForegroundProcess.isClaude(arguments: []))
	}

	@Test func mentioningClaudeIsNotClaude() {
		// Editing a Claude config file must not read as a running session.
		#expect(!PtyForegroundProcess.isClaude(arguments: ["vim", "/Users/me/.claude/settings.json"]))
		#expect(!PtyForegroundProcess.isClaude(arguments: ["git", "commit", "claude"]))
	}

	@Test func closedDescriptorIsUnknown() {
		#expect(PtyForegroundProcess.isClaude(ptyDescriptor: -1) == nil)
	}
}
