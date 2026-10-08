import Testing
@testable import ProcessExecution

struct GitCommandLogTests {
	@Test(arguments: [
		["--no-optional-locks", "status", "--porcelain"],
		["-C", "/repo", "log", "--oneline"],
		["rev-parse", "--verify", "--quiet", "main"],
		["config", "--get", "remote.origin.url"],
		["stash", "list"],
		["worktree", "list", "--porcelain"],
		["symbolic-ref", "--quiet", "--short", "HEAD"],
		["branch", "--show-current"],
		["branch", "--list", "feature/*"],
		["remote", "get-url", "origin"],
	])
	func readOnlyCommands(_ arguments: [String]) {
		#expect(GitCommandLog.isReadOnly(arguments))
	}

	@Test(arguments: [
		["push", "--set-upstream", "origin", "feature"],
		["pull", "--prune"],
		["fetch", "origin"],
		["-c", "core.editor=true", "merge", "origin/main"],
		["checkout", "-b", "feature"],
		["stash", "-u"],
		["stash", "pop"],
		["worktree", "add", "../wt", "-b", "feature"],
		["config", "branch.feature.pr-ref", "refs/pull/1/head"],
		["branch", "-D", "feature"],
		["branch", "feature"],
		["symbolic-ref", "HEAD", "refs/heads/main"],
		["commit", "-m", "Message"],
		["some-future-command"],
	])
	func changingCommands(_ arguments: [String]) {
		#expect(!GitCommandLog.isReadOnly(arguments))
	}

	@Test
	func commandLineQuotesAndFlattensArguments() {
		#expect(
			GitCommandLog.commandLine(["commit", "-m", "Fix it\n\nBody", "--author=O'Neil"])
				== #"commit -m 'Fix it\n\nBody' '--author=O'\''Neil'"#
		)
	}
}
