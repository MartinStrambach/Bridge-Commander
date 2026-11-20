import Foundation
import ProcessExecution

/// What the current branch changed since it left the default branch: every path that differs
/// between the merge-base and the working tree (committed, staged and unstaged alike), plus
/// untracked files.
public struct GitBranchChanges: Equatable, Sendable {
	/// The ref the branch was compared with, e.g. "origin/master".
	public var baseRef: String
	/// The commit the branch and `baseRef` last shared.
	public var mergeBase: String
	/// Paths relative to the working tree's root.
	public var changedPaths: [String]

	public init(baseRef: String, mergeBase: String, changedPaths: [String]) {
		self.baseRef = baseRef
		self.mergeBase = mergeBase
		self.changedPaths = changedPaths
	}
}

/// Read-only: nothing here writes to the repository or touches the network.
public nonisolated enum GitBranchChangesHelper {

	/// The changes of the branch checked out at `path` against the default branch (the
	/// configured one, else what `GitDefaultBranchDetector.detectDefaultBranch` resolves, which
	/// counts local branches too, so a repository without a remote on `main` resolves). The
	/// remote-tracking branch is preferred, so a stale local default branch does not count its
	/// missing commits as changes; the local branch stands in for a repository without a remote.
	public static func changes(at path: String, configuredDefaultBranch: String) async throws -> GitBranchChanges {
		let defaultBranch = await GitDefaultBranchDetector.detectDefaultBranch(
			at: path,
			configured: configuredDefaultBranch
		)
		guard let baseRef = await firstExistingRef(["origin/\(defaultBranch)", defaultBranch], at: path) else {
			throw GitError.logFailed("Neither origin/\(defaultBranch) nor \(defaultBranch) exists")
		}

		let mergeBaseResult = await ProcessRunner.runGit(arguments: ["merge-base", "HEAD", baseRef], at: path)
		let mergeBase = mergeBaseResult.trimmedOutput
		guard mergeBaseResult.success, !mergeBase.isEmpty else {
			throw GitError.logFailed("No common ancestor with \(baseRef): \(mergeBaseResult.trimmedError)")
		}

		// `git diff <commit>` compares the working tree with the commit, so committed, staged and
		// unstaged changes all show. Without renames, a moved file counts for both its folders.
		let diff = await ProcessRunner.runGit(
			arguments: ["--no-optional-locks", "diff", "--name-only", "--no-renames", "-z", mergeBase],
			at: path
		)
		guard diff.success else {
			throw GitError.logFailed(diff.trimmedError)
		}
		let untracked = await ProcessRunner.runGit(
			arguments: ["ls-files", "--others", "--exclude-standard", "-z"],
			at: path
		)
		guard untracked.success else {
			throw GitError.logFailed(untracked.trimmedError)
		}

		return GitBranchChanges(
			baseRef: baseRef,
			mergeBase: mergeBase,
			changedPaths: nulSeparated(diff.outputString) + nulSeparated(untracked.outputString)
		)
	}

	/// Which of `folders` (relative to the root) exist in `commit`.
	///
	/// Lists every folder under the folders' top-level ones and intersects. Naming the folders
	/// as pathspecs instead goes wrong when one lies inside another (a module nested in a
	/// module): `ls-tree` then lists the outer folder's children in place of the folder itself.
	public static func existingFolders(
		_ folders: [String],
		at commit: String,
		in repositoryPath: String
	) async throws -> Set<String> {
		let topLevel = Set(folders.compactMap { $0.split(separator: "/").first.map(String.init) })
		guard !topLevel.isEmpty else {
			return []
		}

		// Literal pathspecs: a folder name is never a glob.
		let result = await ProcessRunner.runGit(
			arguments: ["--literal-pathspecs", "ls-tree", "-r", "-d", "--name-only", "-z", commit, "--"]
				+ topLevel.sorted(),
			at: repositoryPath
		)
		guard result.success else {
			throw GitError.logFailed(result.trimmedError)
		}
		return Set(nulSeparated(result.outputString)).intersection(folders)
	}

	private static func firstExistingRef(_ candidates: [String], at path: String) async -> String? {
		for candidate in candidates {
			let result = await ProcessRunner.runGit(
				arguments: ["rev-parse", "--verify", "--quiet", "\(candidate)^{commit}"],
				at: path
			)
			if result.success {
				return candidate
			}
		}
		return nil
	}

	static func nulSeparated(_ output: String) -> [String] {
		output.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)
	}
}
