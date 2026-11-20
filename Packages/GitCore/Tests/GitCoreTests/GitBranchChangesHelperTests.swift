import Foundation
import ProcessExecution
import Testing

@testable import GitCore

/// What a branch changed since it left the default branch, against a real repository: committed,
/// staged, unstaged and untracked changes all count, and folder existence at the merge-base holds
/// for a folder nested in another.
@Suite("GitBranchChangesHelper")
struct GitBranchChangesHelperTests {

	/// A repository without a remote, on `main`, with `outer/inner` committed there and a
	/// `feature` branch checked out.
	private struct Repository {
		let path: String

		init() async throws {
			path = NSTemporaryDirectory() + "GitBranchChangesHelperTests-" + UUID().uuidString
			try FileManager.default.createDirectory(atPath: path + "/outer/inner", withIntermediateDirectories: true)
			try "a".write(toFile: path + "/outer/inner/file.txt", atomically: true, encoding: .utf8)
			try "b".write(toFile: path + "/outer/file.txt", atomically: true, encoding: .utf8)
			try await git("init", "--initial-branch=main")
			try await git("config", "user.email", "test@example.com")
			try await git("config", "user.name", "Test")
			try await git("config", "commit.gpgsign", "false")
			try await git("add", ".")
			try await git("commit", "-m", "base")
			try await git("checkout", "-b", "feature")
		}

		@discardableResult
		func git(_ arguments: String...) async throws -> String {
			let result = await ProcessRunner.runGit(arguments: arguments, at: path)
			guard result.success else {
				throw GitError.logFailed("git \(arguments.joined(separator: " ")): \(result.errorString)")
			}
			return result.outputString.trimmingCharacters(in: .whitespacesAndNewlines)
		}

		func write(_ text: String, to relativePath: String) throws {
			let url = URL(filePath: path).appending(path: relativePath)
			try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
			try text.write(to: url, atomically: true, encoding: .utf8)
		}

		func remove() {
			try? FileManager.default.removeItem(atPath: path)
		}
	}

	@Test
	func changesSinceTheMergeBaseWithALocalMainBranch() async throws {
		let repository = try await Repository()
		defer { repository.remove() }

		try repository.write("committed", to: "added/committed.txt")
		try await repository.git("add", ".")
		try await repository.git("commit", "-m", "feature work")
		try repository.write("staged", to: "outer/inner/file.txt")
		try await repository.git("add", "outer/inner/file.txt")
		try repository.write("unstaged", to: "outer/file.txt")
		try repository.write("untracked", to: "new/untracked.txt")

		let changes = try await GitBranchChangesHelper.changes(at: repository.path, configuredDefaultBranch: "")

		#expect(changes.baseRef == "main")
		#expect(changes.mergeBase == (try await repository.git("rev-parse", "main")))
		#expect(Set(changes.changedPaths) == [
			"added/committed.txt",
			"outer/inner/file.txt",
			"outer/file.txt",
			"new/untracked.txt",
		])
	}

	@Test
	func existingFoldersHoldsForNestedFolders() async throws {
		let repository = try await Repository()
		defer { repository.remove() }
		let base = try await repository.git("rev-parse", "HEAD")

		let existing = try await GitBranchChangesHelper.existingFolders(
			["outer", "outer/inner", "outer/missing", "absent"],
			at: base,
			in: repository.path
		)

		#expect(existing == ["outer", "outer/inner"])
	}

	@Test
	func aMissingDefaultBranchIsAnError() async throws {
		let repository = try await Repository()
		defer { repository.remove() }

		await #expect(throws: GitError.self) {
			try await GitBranchChangesHelper.changes(at: repository.path, configuredDefaultBranch: "develop")
		}
	}
}
