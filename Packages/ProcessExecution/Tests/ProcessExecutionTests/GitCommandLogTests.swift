import ActivityLog
import Foundation
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

	private func entry(
		_ arguments: [String],
		exitCode: Int32,
		wasCancelled: Bool = false,
		includesReadOnly: Bool = false
	) -> GitCommandLog.Entry? {
		GitCommandLog.entry(
			arguments: arguments,
			repositoryPath: "/repo",
			result: ProcessResult(exitCode: exitCode, output: Data(), error: Data("fatal: oops".utf8), wasCancelled: wasCancelled),
			duration: .milliseconds(5),
			includesReadOnly: includesReadOnly
		)
	}

	/// A superseded refresh ends with its `git status` terminated (exit 15), which used to be
	/// recorded as an error on every refresh.
	@Test
	func aCancelledReadOnlyCommandIsNotRecorded() {
		#expect(entry(["--no-optional-locks", "status"], exitCode: SIGTERM, wasCancelled: true) == nil)
		#expect(
			entry(["status"], exitCode: SIGTERM, wasCancelled: true, includesReadOnly: true)?.category == .git
		)
		#expect(
			entry(["status"], exitCode: SIGTERM, wasCancelled: true, includesReadOnly: true)?.message
				.contains("→ cancelled in") == true
		)
	}

	@Test
	func aCancelledCommandThatChangesSomethingIsRecordedAsCancelled() {
		let recorded = entry(["pull", "--prune"], exitCode: SIGTERM, wasCancelled: true)
		#expect(recorded?.category == .git)
		#expect(recorded?.details == nil)
	}

	/// A signal the app did not send is still a failure.
	@Test
	func aCommandKilledWithoutACancellationIsAnError() {
		#expect(entry(["status"], exitCode: SIGTERM)?.category == .error)
		#expect(entry(["status"], exitCode: 128)?.details == "fatal: oops")
		#expect(entry(["rev-parse", "--verify", "--quiet", "x"], exitCode: 1) == nil)
	}

	@Test
	func commandLineQuotesAndFlattensArguments() {
		#expect(
			GitCommandLog.commandLine(["commit", "-m", "Fix it\n\nBody", "--author=O'Neil"])
				== #"commit -m 'Fix it\n\nBody' '--author=O'\''Neil'"#
		)
	}
}
