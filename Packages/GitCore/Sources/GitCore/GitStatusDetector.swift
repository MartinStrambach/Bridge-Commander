import Foundation
import ProcessExecution

/// Parsed result of `git status --porcelain=v2 [--branch]`.
public nonisolated struct GitPorcelainStatus {

	// MARK: - Branch (populated only when run with --branch)

	public let branch: String?
	public let hasRemoteBranch: Bool
	/// Ahead of the upstream, or — for a branch with no upstream — commits on no remote-tracking
	/// branch at all (`GitStatusDetector.getStatus` fills that in; parsing alone leaves it 0).
	public internal(set) var unpushedCount: Int
	public let behindCount: Int

	// MARK: - File changes

	public let staged: [FileChange]
	public let unstaged: [FileChange]

	/// False when the underlying git process failed — callers should ignore all fields.
	public let didSucceed: Bool

	public var stagedCount: Int {
		staged.count
	}

	public var unstagedCount: Int {
		unstaged.count
	}

	// MARK: - Init

	public init(parsing output: String, didSucceed: Bool = true) {
		var branch: String?
		var hasRemoteBranch = false
		var unpushedCount = 0
		var behindCount = 0
		var staged: [FileChange] = []
		var unstaged: [FileChange] = []

		for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
			if line.hasPrefix("# branch.head ") {
				let name = String(line.dropFirst("# branch.head ".count))
				if name != "(detached)" {
					branch = name
				}
			}
			else if line.hasPrefix("# branch.upstream ") {
				hasRemoteBranch = true
			}
			else if line.hasPrefix("# branch.ab ") {
				// "# branch.ab +N -M" — N ahead (unpushed), M behind
				let parts = String(line.dropFirst("# branch.ab ".count)).split(separator: " ")
				if parts.count == 2 {
					unpushedCount = Int(parts[0].dropFirst()) ?? 0 // drop "+"
					behindCount = Int(parts[1].dropFirst()) ?? 0 // drop "-"
				}
			}
			else if line.hasPrefix("? ") {
				// Untracked — "? path"
				let filePath = String(line.dropFirst(2))
				if !filePath.isEmpty {
					unstaged.append(FileChange(path: filePath, status: .untracked))
				}
			}
			else if line.hasPrefix("u ") {
				// Unmerged (conflicted) — "u XY sub m1 m2 m3 mW h1 h2 h3 path"
				let parts = line.split(separator: " ", maxSplits: 10)
				guard parts.count == 11 else {
					continue
				}

				let filePath = String(parts[10])
				if !filePath.isEmpty {
					unstaged.append(FileChange(path: filePath, status: .conflicted))
				}
			}
			else if line.hasPrefix("1 ") {
				// Ordinary changed — "1 XY sub mH mI mW hH hI path"
				let parts = line.split(separator: " ", maxSplits: 8)
				guard parts.count == 9 else {
					continue
				}

				let xy = parts[1]
				guard xy.count == 2 else {
					continue
				}

				let x = xy[xy.startIndex]
				let y = xy[xy.index(after: xy.startIndex)]
				let filePath = String(parts[8])
				guard !filePath.isEmpty else {
					continue
				}

				if x != ".", let status = FileChangeStatus(rawValue: String(x)) {
					staged.append(FileChange(path: filePath, status: status))
				}
				if y != ".", let status = FileChangeStatus(rawValue: String(y)) {
					unstaged.append(FileChange(path: filePath, status: status))
				}
			}
			else if line.hasPrefix("2 ") {
				// Renamed/copied — "2 XY sub mH mI mW hH hI score newPath\torigPath"
				// Split by space gives 10 parts (index 0–9); the tab-separated paths are the last part.
				let parts = line.split(separator: " ", maxSplits: 9)
				guard parts.count == 10 else {
					continue
				}

				let xy = parts[1]
				guard xy.count == 2 else {
					continue
				}

				let x = xy[xy.startIndex]
				let y = xy[xy.index(after: xy.startIndex)]
				let pathField = parts[9]
				let paths = pathField.split(separator: "\t", maxSplits: 1)
				guard let newPath = paths.first.map(String.init), !newPath.isEmpty else {
					continue
				}

				let origPath = paths.count > 1 ? String(paths[1]) : newPath

				if x != ".", let status = FileChangeStatus(rawValue: String(x)) {
					staged.append(FileChange(path: newPath, status: status, oldPath: origPath))
				}
				if y != ".", let status = FileChangeStatus(rawValue: String(y)) {
					unstaged.append(FileChange(path: newPath, status: status))
				}
			}
		}

		self.branch = branch
		self.hasRemoteBranch = hasRemoteBranch
		self.unpushedCount = unpushedCount
		self.behindCount = behindCount
		self.staged = staged
		self.unstaged = unstaged
		self.didSucceed = didSucceed
	}
}

// MARK: -

public nonisolated enum GitStatusDetector {
	/// Runs `git status --porcelain=v2 --branch` and returns the parsed result.
	public static func getStatus(at path: String) async -> GitPorcelainStatus {
		let result = await ProcessRunner.runGit(
			arguments: ["status", "--porcelain=v2", "--branch", "--untracked-files=all"],
			at: path
		)
		var status = GitPorcelainStatus(parsing: result.outputString, didSucceed: result.success)
		// git reports ahead/behind only against an upstream, so a branch that was never pushed
		// would read as having nothing to push.
		if status.didSucceed, status.branch != nil, !status.hasRemoteBranch {
			status.unpushedCount = await countCommitsOnNoRemote(at: path)
		}
		return status
	}

	/// Commits reachable from HEAD but from no remote-tracking branch. 0 when the repository has
	/// no remote-tracking branches at all: there is nothing to measure against, and every commit
	/// in its history would count.
	static func countCommitsOnNoRemote(at path: String) async -> Int {
		let remotes = await ProcessRunner.runGit(
			arguments: ["for-each-ref", "--count=1", "--format=%(refname)", "refs/remotes"],
			at: path
		)
		guard remotes.success, !remotes.trimmedOutput.isEmpty else {
			return 0
		}

		let result = await ProcessRunner.runGit(
			arguments: ["rev-list", "--count", "HEAD", "--not", "--remotes"],
			at: path
		)
		guard result.success else {
			return 0
		}
		return Int(result.trimmedOutput) ?? 0
	}
}
