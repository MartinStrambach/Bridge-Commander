import Foundation
import ProcessExecution

public nonisolated enum GitPushHelper {
	public struct PushResult: Equatable, Sendable {
		public let isUpToDate: Bool
		public let message: String

		public init(isUpToDate: Bool, message: String) {
			self.isUpToDate = isUpToDate
			self.message = message
		}
	}

	public enum Mode: Equatable, Sendable {
		/// `git push`, as configured.
		case normal
		/// Replaces the rejected remote branch with the local one, for a branch whose history was
		/// rewritten (rebase, amend). Pushes exactly that refspec, whatever HEAD is on by now and
		/// whatever `push.default` would pick. `--force-with-lease` refuses when the remote moved
		/// past our remote-tracking ref (someone pushed since our last fetch); `--force-if-includes`
		/// also refuses when that ref was fetched but never built on — a background fetch would
		/// otherwise satisfy the lease and let the push drop the commits it brought in.
		case forceWithLease(GitRejectedPush)
	}

	/// Pushes commits to the remote repository
	/// - Parameters:
	///   - path: The path to the Git repository
	///   - mode: A plain push, or a force push with lease of one rejected branch
	/// - Returns: PushResult with information about the push operation
	/// - Throws: `GitError.pushFailed` if the push fails
	public static func push(at path: String, mode: Mode = .normal) async throws -> PushResult {
		let arguments: [String] =
			switch mode {
			case .normal:
				["push"]
			case let .forceWithLease(rejected):
				[
					"push", "--force-with-lease", "--force-if-includes",
					await pushRemote(for: rejected.localBranch, at: path),
					"refs/heads/\(rejected.localBranch):refs/heads/\(rejected.remoteBranch)",
				]
			}
		let result = await ProcessRunner.runGit(arguments: arguments, at: path)

		let output = result.trimmedOutput
		let errorOutput = result.trimmedError

		guard result.success else {
			throw GitError.pushFailed(errorOutput)
		}

		// Check if everything is up to date
		let combinedOutput = output + errorOutput
		let isUpToDate = combinedOutput.contains("Everything up-to-date")

		return PushResult(
			isUpToDate: isUpToDate,
			message: combinedOutput
		)
	}

	/// The remote a plain `git push` of `branch` goes to: `branch.<name>.pushRemote`, then
	/// `remote.pushDefault`, then `branch.<name>.remote`, then `origin` (git-config(1)).
	static func pushRemote(for branch: String, at path: String) async -> String {
		for key in ["branch.\(branch).pushRemote", "remote.pushDefault", "branch.\(branch).remote"] {
			let result = await ProcessRunner.runGit(arguments: ["config", "--get", key], at: path)
			let remote = result.trimmedOutput
			if result.success, !remote.isEmpty {
				return remote
			}
		}
		return "origin"
	}
}
