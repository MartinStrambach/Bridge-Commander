import ActivityLog
import Foundation

/// Records git commands in the activity log.
///
/// Rows poll status, log and diff for every repository on each refresh, so read-only commands are
/// recorded only when they fail — unless Settings asks for all of them. Commands that change
/// something (push, pull, fetch, merge, checkout, stash, commit, worktree add, …) are always
/// recorded, with their exit code, and stderr when they fail.
nonisolated enum GitCommandLog {
	private static let maximumArgumentLength = 200
	private static let maximumErrorLength = 2000

	static func record(arguments: [String], repositoryPath: String, result: ProcessResult, duration: Duration) {
		let readOnly = isReadOnly(arguments)
		// Exit code 1 is how read-only probes answer "no" (`rev-parse --verify --quiet`,
		// `merge-base --is-ancestor`, `config --get`, `check-ignore`); git's own failures are 128.
		let failed = readOnly ? !(0 ... 1).contains(result.exitCode) : !result.success
		guard !readOnly || failed || ActivityLog.includesReadOnlyGitCommands else {
			return
		}

		ActivityLog.shared.record(
			failed ? .error : .git,
			"git \(commandLine(arguments)) (in \(repositoryPath)) → exit \(result.exitCode) in \(duration.activityLogDescription)",
			details: failed ? truncated(result.trimmedError, to: maximumErrorLength) : nil
		)
	}

	/// The arguments as they would be typed, quoted where needed; a long argument (a commit
	/// message) is cut short and a multi-line one kept on one line.
	static func commandLine(_ arguments: [String]) -> String {
		arguments.map { argument in
			let single = truncated(argument.replacing("\n", with: "\\n"), to: maximumArgumentLength)
			return single.isEmpty || single.contains(where: { $0.isWhitespace || $0 == "'" || $0 == "\"" })
				? "'\(single.replacing("'", with: "'\\''"))'"
				: single
		}
		.joined(separator: " ")
	}

	private static func truncated(_ text: String, to length: Int) -> String {
		text.count > length ? text.prefix(length) + "…" : text
	}

	// MARK: - Classification

	/// Subcommands that never change the repository or a remote.
	private static let readOnlySubcommands: Set<String> = [
		"blame", "cat-file", "check-attr", "check-ignore", "count-objects", "describe", "diff",
		"diff-files", "diff-index", "diff-tree", "for-each-ref", "grep", "help", "log", "ls-files",
		"ls-remote", "ls-tree", "merge-base", "name-rev", "rev-list", "rev-parse", "shortlog", "show",
		"show-ref", "status", "var", "version",
	]

	/// Global options that take the next argument as their value (`git -C <path> status`).
	private static let globalOptionsWithValue: Set<String> = ["-C", "-c", "--git-dir", "--work-tree", "--namespace"]

	/// Whether `arguments` only reads. Anything not known to be read-only counts as a change, so
	/// an unrecognized command is recorded rather than lost.
	static func isReadOnly(_ arguments: [String]) -> Bool {
		var remaining = arguments[...]
		while let first = remaining.first, first.hasPrefix("-") {
			remaining = remaining.dropFirst(globalOptionsWithValue.contains(first) ? 2 : 1)
		}
		guard let subcommand = remaining.first else {
			return true
		}

		let rest = Array(remaining.dropFirst())
		let positionals = rest.filter { !$0.hasPrefix("-") }
		switch subcommand {
		case _ where readOnlySubcommands.contains(subcommand):
			return true

		case "config":
			return rest.contains { ["--get", "--get-all", "--get-regexp", "--get-urlmatch", "--list", "-l"].contains($0) }

		case "stash":
			return ["list", "show"].contains(rest.first)

		case "worktree":
			return rest.first == "list"

		case "remote":
			return rest.isEmpty || rest == ["-v"] || ["get-url", "show"].contains(rest.first)

		case "symbolic-ref":
			// `symbolic-ref HEAD` reads; `symbolic-ref HEAD refs/heads/main` writes.
			return positionals.count <= 1 && !rest.contains { $0 == "-d" || $0 == "--delete" }

		case "branch":
			let changes = ["-d", "-D", "--delete", "-m", "-M", "--move", "-c", "-C", "--copy", "-f", "--force",
			               "-u", "--set-upstream-to", "--unset-upstream", "--edit-description"]
			let lists = ["--list", "-l", "--contains", "--no-contains", "--merged", "--no-merged", "--points-at"]
			guard !rest.contains(where: { changes.contains($0) || $0.hasPrefix("--set-upstream-to=") }) else {
				return false
			}
			// A bare name creates a branch; with a listing option it is a pattern or a commit.
			return positionals.isEmpty || rest.contains { lists.contains($0) }

		case "tag":
			return rest.isEmpty || rest.contains { $0 == "-l" || $0 == "--list" }

		default:
			return false
		}
	}
}
