import Foundation
import ProcessExecution

/// A git command that applies a commit and can stop half-way, leaving `<NAME>_HEAD` and the
/// sequencer state behind until it is committed or aborted.
public enum GitSequencerOperation: String, Equatable, Hashable, Sendable {
	case cherryPick = "cherry-pick"
	case revert

	/// The pseudo-ref git leaves while the operation is stopped.
	var headRef: String {
		switch self {
		case .cherryPick:
			"CHERRY_PICK_HEAD"
		case .revert:
			"REVERT_HEAD"
		}
	}
}

/// How a cherry-pick or revert ended.
public enum GitSequencerOutcome: Equatable, Sendable {
	/// The new commit is on the current branch.
	case committed
	/// Stopped with these files conflicted. Nothing is committed yet; the user resolves and
	/// commits, or aborts.
	case conflicts([String])
}

/// The commit graph's write actions: everything that acts on a commit picked in the graph.
public nonisolated enum GitCommitActionHelper {

	// MARK: - Cherry-pick / Revert

	/// Applies `commit` onto the current branch (`cherry-pick`) or adds a commit undoing it
	/// (`revert`). A merge commit is taken against its first parent (`-m 1`) — the same side
	/// the graph's diff shows for it; git refuses a merge without `-m`.
	///
	/// Stopping on conflicts is an outcome, not an error. Stopping for any other reason (the
	/// commit's changes are already there, so the result would be empty) unwinds the operation
	/// before throwing, so a failure never leaves a half-done cherry-pick or revert behind.
	public static func apply(
		_ operation: GitSequencerOperation,
		commit: GitLogCommit,
		at path: String
	) async throws -> GitSequencerOutcome {
		let result = await ProcessRunner.runGit(
			arguments: arguments(for: operation, commit: commit),
			at: path
		)

		guard !result.success else {
			return .committed
		}

		let conflicted = await unmergedFiles(at: path)
		if !conflicted.isEmpty {
			return .conflicts(conflicted)
		}

		let stoppedEmpty = await isInProgress(operation, at: path)
		if stoppedEmpty {
			_ = await ProcessRunner.runGit(arguments: [operation.rawValue, "--abort"], at: path)
		}

		let message = describeFailure(
			stderr: result.trimmedError,
			stdout: result.trimmedOutput,
			stoppedEmpty: stoppedEmpty
		)
		throw error(for: operation, message: message)
	}

	/// Abandons a stopped cherry-pick or revert, putting the branch, index and working tree back
	/// as they were before it started.
	public static func abort(_ operation: GitSequencerOperation, at path: String) async throws {
		let result = await ProcessRunner.runGit(arguments: [operation.rawValue, "--abort"], at: path)
		guard result.success else {
			throw error(for: operation, message: "Could not abort: \(result.trimmedError)")
		}
	}

	private static func error(for operation: GitSequencerOperation, message: String) -> GitError {
		switch operation {
		case .cherryPick:
			.cherryPickFailed(message)
		case .revert:
			.revertFailed(message)
		}
	}

	static func arguments(for operation: GitSequencerOperation, commit: GitLogCommit) -> [String] {
		var arguments = [operation.rawValue]
		if operation == .revert {
			// The default would open an editor for the message, and there is no terminal to open it in.
			arguments.append("--no-edit")
		}
		if commit.isMerge {
			arguments += ["-m", "1"]
		}
		return arguments + [commit.hash]
	}

	static func describeFailure(stderr: String, stdout: String, stoppedEmpty: Bool) -> String {
		if stoppedEmpty {
			return "Its changes are already on the current branch, so there was nothing to commit."
		}
		if !stderr.isEmpty {
			return stderr
		}
		return stdout.isEmpty ? "Git stopped without saying why. Check the repository state." : stdout
	}

	private static func unmergedFiles(at path: String) async -> [String] {
		let result = await ProcessRunner.runGit(
			arguments: ["diff", "--name-only", "--diff-filter=U"],
			at: path
		)
		return result.outputString
			.split(separator: "\n")
			.map(String.init)
			.filter { !$0.isEmpty }
	}

	private static func isInProgress(_ operation: GitSequencerOperation, at path: String) async -> Bool {
		await ProcessRunner.runGit(
			arguments: ["rev-parse", "--quiet", "--verify", operation.headRef],
			at: path
		).success
	}

	// MARK: - Checkout

	/// Detaches HEAD at `hash`. Git refuses when local changes would be overwritten.
	public static func checkoutDetached(hash: String, at path: String) async throws {
		let result = await ProcessRunner.runGit(arguments: ["checkout", "--detach", hash], at: path)
		guard result.success else {
			throw GitError.checkoutFailed(result.trimmedError)
		}
	}

	/// Checks out the local branch a remote one (`origin/feature`) stands for: the existing local
	/// branch of that name if there is one, otherwise a new one tracking the remote.
	public static func checkout(remoteBranch: String, at path: String) async throws {
		guard let localName = localBranchName(forRemoteBranch: remoteBranch) else {
			throw GitError.checkoutFailed("'\(remoteBranch)' does not name a remote branch.")
		}

		let localExists = await ProcessRunner.runGit(
			arguments: ["show-ref", "--verify", "--quiet", "refs/heads/\(localName)"],
			at: path
		).success
		if localExists {
			try await GitCheckoutHelper.checkout(branch: localName, at: path)
			return
		}

		let result = await ProcessRunner.runGit(
			arguments: ["checkout", "-b", localName, "--track", remoteBranch],
			at: path
		)
		guard result.success else {
			throw GitError.checkoutFailed(result.trimmedError)
		}
	}

	/// "origin/feature/x" → "feature/x": everything after the remote's name.
	public static func localBranchName(forRemoteBranch remoteBranch: String) -> String? {
		guard
			let slash = remoteBranch.firstIndex(of: "/"),
			slash != remoteBranch.startIndex
		else {
			return nil
		}

		let localName = remoteBranch[remoteBranch.index(after: slash)...]
		return localName.isEmpty ? nil : String(localName)
	}

	// MARK: - Branch

	/// Creates `name` at `startPoint`, and switches to it when `checkout` is set.
	public static func createBranch(
		named name: String,
		at startPoint: String,
		checkout: Bool,
		repositoryPath: String
	) async throws {
		// Git rejects such a name anyway, but as an argument it would be read as an option first.
		guard !name.hasPrefix("-") else {
			throw GitError.branchCreationFailed("'\(name)' is not a valid branch name.")
		}

		let arguments = checkout
			? ["checkout", "-b", name, startPoint]
			: ["branch", name, startPoint]
		let result = await ProcessRunner.runGit(arguments: arguments, at: repositoryPath)
		guard result.success else {
			throw GitError.branchCreationFailed(result.trimmedError)
		}
	}
}
