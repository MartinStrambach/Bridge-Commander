import Foundation
import ProcessExecution
import Testing

@testable import GitCore

/// `git worktree remove` can fail in two ways that must not be confused: refusing before it has
/// touched anything, and failing to delete a file after the point of no return — it then exits
/// with an error although the worktree is gone from the repository.
@Suite("GitWorktreeRemover")
struct GitWorktreeRemoverTests {

	/// A repository on `main` with a linked worktree on `feature`.
	private struct Repository {
		let root: String
		let path: String
		/// As a scan reports it: git resolves the path (`/private/var/…`).
		private(set) var worktreePath: String

		init() async throws {
			root = NSTemporaryDirectory() + "GitWorktreeRemoverTests-" + UUID().uuidString
			path = root + "/repo"
			worktreePath = root + "/worktree"
			try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
			try await git("init", "--initial-branch=main")
			try await git("config", "user.email", "test@example.com")
			try await git("config", "user.name", "Test")
			try await git("config", "commit.gpgsign", "false")
			try await git("commit", "--allow-empty", "-m", "base")
			try await git("worktree", "add", "-b", "feature", worktreePath)
			let scanned = await GitWorktreeScanner.listWorktrees(forRepo: path).first { $0.isWorktree }
			worktreePath = try #require(scanned).path
		}

		@discardableResult
		func git(_ arguments: String...) async throws -> String {
			let result = await ProcessRunner.runGit(arguments: arguments, at: path)
			guard result.success else {
				throw GitError.logFailed("git \(arguments.joined(separator: " ")): \(result.errorString)")
			}
			return result.outputString.trimmingCharacters(in: .whitespacesAndNewlines)
		}

		func isWorktreeListed() async -> Bool {
			await GitWorktreeScanner.listWorktrees(forRepo: path).contains { $0.isWorktree }
		}

		/// A folder in the worktree whose file cannot be deleted, as one a running program holds.
		func addUndeletableFile() throws -> String {
			let folder = worktreePath + "/locked"
			try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
			try "kept".write(toFile: folder + "/file", atomically: true, encoding: .utf8)
			try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder)
			return folder
		}

		func remove(unlocking folder: String? = nil) {
			if let folder {
				try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder)
			}
			try? FileManager.default.removeItem(atPath: root)
		}
	}

	@Test("a clean worktree is removed")
	func removesACleanWorktree() async throws {
		let repository = try await Repository()
		defer { repository.remove() }

		let outcome = try await GitWorktreeRemover.removeWorktree(name: "feature", path: repository.worktreePath)

		#expect(outcome == .removed)
		#expect(await !repository.isWorktreeListed())
		#expect(!FileManager.default.fileExists(atPath: repository.worktreePath))
	}

	@Test("a worktree git refuses to remove is an error, and stays")
	func refusalThrows() async throws {
		let repository = try await Repository()
		defer { repository.remove() }
		try "new".write(toFile: repository.worktreePath + "/untracked", atomically: true, encoding: .utf8)

		await #expect(throws: GitError.self) {
			try await GitWorktreeRemover.removeWorktree(name: "feature", path: repository.worktreePath)
		}
		#expect(await repository.isWorktreeListed())
	}

	@Test("a worktree git unregistered without deleting every file is removed, leaving files")
	func partialDeletionIsARemoval() async throws {
		let repository = try await Repository()
		let locked = try repository.addUndeletableFile()
		defer { repository.remove(unlocking: locked) }

		let outcome = try await GitWorktreeRemover.removeWorktree(
			name: "feature",
			path: repository.worktreePath,
			force: true
		)

		guard case let .removedLeavingFiles(message) = outcome else {
			Issue.record("expected files to be left behind, got \(outcome)")
			return
		}

		#expect(message.contains("failed to delete"))
		#expect(await !repository.isWorktreeListed())
		#expect(FileManager.default.fileExists(atPath: locked + "/file"))
	}

	@Test("a folder that is no worktree of the repository is an error")
	func unknownWorktreeThrows() async throws {
		let repository = try await Repository()
		defer { repository.remove() }
		try await repository.git("worktree", "remove", repository.worktreePath)
		try FileManager.default.createDirectory(atPath: repository.worktreePath, withIntermediateDirectories: true)

		await #expect(throws: GitError.self) {
			try await GitWorktreeRemover.removeWorktree(name: "feature", path: repository.worktreePath)
		}
	}
}
