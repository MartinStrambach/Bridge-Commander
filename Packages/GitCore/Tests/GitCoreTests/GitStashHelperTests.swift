import Foundation
import ProcessExecution
import Testing

@testable import GitCore

// The stash list is shared by every worktree, so a stash pushed or dropped in another one between
// the menu's check and a click shifts the `stash@{n}` the menu found. These run real git.
@Suite("GitStashHelper")
struct GitStashHelperTests {

	/// A repository on `main` with one commit.
	private struct Repository {
		let path: String

		init() async throws {
			path = NSTemporaryDirectory() + "GitStashHelperTests-" + UUID().uuidString
			try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
			try await git("init", "--initial-branch=main")
			try await git("config", "user.email", "test@example.com")
			try await git("config", "user.name", "Test")
			try await git("config", "commit.gpgsign", "false")
			try await git("commit", "--allow-empty", "-m", "base")
		}

		@discardableResult
		func git(_ arguments: String...) async throws -> String {
			let result = await ProcessRunner.runGit(arguments: arguments, at: path)
			guard result.success else {
				throw GitError.logFailed("git \(arguments.joined(separator: " ")): \(result.errorString)")
			}
			return result.outputString.trimmingCharacters(in: .whitespacesAndNewlines)
		}

		/// Stashes a new untracked file, as the menu's Stash does (`git stash -u`).
		func stash(_ file: String) async throws {
			try Data(file.utf8).write(to: URL(fileURLWithPath: path).appendingPathComponent(file))
			try await GitStashHelper.stash(at: path)
		}

		func remove() {
			try? FileManager.default.removeItem(atPath: path)
		}
	}

	@Test("clearing drops the stash that was found, after a newer stash shifted its index")
	func dropFollowsTheEntryAfterAShift() async throws {
		let repository = try await Repository()
		defer { repository.remove() }
		try await repository.stash("main-work")
		let found = try #require(await GitStashHelper.findStash(at: repository.path, branch: "main"))
		#expect(found.reference == "stash@{0}")

		// Another worktree stashes in between: `main`'s stash is now stash@{1}.
		try await repository.git("checkout", "-b", "other")
		try await repository.stash("other-work")

		try await GitStashHelper.stashDrop(at: repository.path, entry: found)

		let left = GitStashListParser.parse(try await repository.git("stash", "list"))
		#expect(left.map(\.branch) == ["other"])
	}

	@Test("popping a stash that is gone fails without touching the one now in its place")
	func popOfAGoneEntryFails() async throws {
		let repository = try await Repository()
		defer { repository.remove() }
		try await repository.stash("first")
		let found = try #require(await GitStashHelper.findStash(at: repository.path, branch: "main"))

		// Dropped elsewhere, and another stash on the same branch took its index.
		try await repository.git("stash", "drop")
		try await repository.stash("second")

		await #expect(throws: GitError.self) {
			try await GitStashHelper.stashPop(at: repository.path, entry: found)
		}
		#expect(GitStashListParser.parse(try await repository.git("stash", "list")).count == 1)
		#expect(!FileManager.default.fileExists(atPath: repository.path + "/second"))
	}
}
