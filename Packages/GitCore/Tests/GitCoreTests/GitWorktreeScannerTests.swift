import Foundation
import ProcessExecution
import Testing

@testable import GitCore

/// The scan's branch must match what `GitStatusDetector.getStatus` reports, or a row flips
/// between the two on every refresh.
@Suite("GitWorktreeScanner")
struct GitWorktreeScannerTests {

	/// A repository on `main` with a linked worktree on `feature`, each branch changing `file`
	/// differently, so rebasing `feature` onto `main` stops on a conflict.
	private struct Repository {
		let path: String
		let worktreePath: String

		init() async throws {
			let root = NSTemporaryDirectory() + "GitWorktreeScannerTests-" + UUID().uuidString
			path = root + "/repo"
			worktreePath = root + "/worktree"
			try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
			try await git("init", "--initial-branch=main")
			try await git("config", "user.email", "test@example.com")
			try await git("config", "user.name", "Test")
			try await git("config", "commit.gpgsign", "false")
			try await commit("base", content: "base", at: path)
			try await git("worktree", "add", "-b", "feature", worktreePath)
			try await commit("feature", content: "feature", at: worktreePath)
			try await commit("main", content: "main", at: path)
		}

		@discardableResult
		func git(_ arguments: String..., at directory: String? = nil) async throws -> String {
			let result = await ProcessRunner.runGit(arguments: arguments, at: directory ?? path)
			guard result.success else {
				throw GitError.logFailed("git \(arguments.joined(separator: " ")): \(result.errorString)")
			}
			return result.outputString.trimmingCharacters(in: .whitespacesAndNewlines)
		}

		func commit(_ message: String, content: String, at directory: String) async throws {
			try content.write(toFile: directory + "/file", atomically: true, encoding: .utf8)
			try await git("add", "file", at: directory)
			try await git("commit", "-m", message, at: directory)
		}

		/// The worktree's entry; git reports paths resolved (`/private/var/…`), so it is matched
		/// by its folder name.
		func scannedWorktree() async -> ScannedRepository? {
			await GitWorktreeScanner.listWorktrees(forRepo: path).first { $0.name == "worktree" }
		}

		func remove() {
			try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent)
		}
	}

	@Test
	func worktreeOnABranchReportsIt() async throws {
		let repository = try await Repository()
		defer { repository.remove() }

		let worktree = await repository.scannedWorktree()

		#expect(worktree?.isWorktree == true)
		#expect(worktree?.branchName == "feature")
	}

	@Test
	func detachedWorktreeIsOnNoBranch() async throws {
		let repository = try await Repository()
		defer { repository.remove() }

		try await repository.git("checkout", "--detach", at: repository.worktreePath)

		let worktree = await repository.scannedWorktree()

		#expect(worktree != nil)
		#expect(worktree?.branchName == nil)
	}

	/// `git worktree list` reports a rebasing worktree as detached, like `git status` does.
	@Test(arguments: [["rebase"], ["rebase", "--apply"]])
	func rebasingWorktreeStaysOnTheBranchBeingRebased(rebase: [String]) async throws {
		let repository = try await Repository()
		defer { repository.remove() }

		_ = await ProcessRunner.runGit(arguments: rebase + ["main"], at: repository.worktreePath)

		let worktree = await repository.scannedWorktree()

		#expect(GitMergeDetector.isGitOperationInProgress(at: repository.worktreePath))
		#expect(worktree?.branchName == "feature")
	}
}
