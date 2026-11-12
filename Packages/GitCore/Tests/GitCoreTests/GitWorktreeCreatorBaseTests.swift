import Foundation
import ProcessExecution
import Testing

@testable import GitCore

@Suite("GitWorktreeCreator — where a new branch starts")
struct GitWorktreeCreatorBaseTests {

	/// An `origin` whose `main` has moved on since it was cloned: the clone's local `main` is one
	/// commit behind `origin/main` once fetched.
	private struct Fixture {
		let root: String
		var origin: String { root + "/origin" }
		var clone: String { root + "/clone" }
		var worktrees: String { root + "/worktrees" }

		init() async throws {
			root = NSTemporaryDirectory() + "GitWorktreeCreatorBaseTests-" + UUID().uuidString
			try FileManager.default.createDirectory(atPath: origin, withIntermediateDirectories: true)
			try await git(at: origin, "init", "--initial-branch=main")
			try await configure(origin)
			try await commit(at: origin, file: "base.txt", message: "base")
			try await git(at: root, "clone", "origin", "clone")
			try await configure(clone)
			try await commit(at: origin, file: "later.txt", message: "later")
		}

		func create(branch: String, startFromOrigin: Bool) async throws -> URL {
			try await GitWorktreeCreator.createWorktree(
				branchName: branch,
				baseBranch: "main",
				repositoryPath: clone,
				startFromOrigin: startFromOrigin,
				worktreeBasePath: worktrees
			)
		}

		func commit(at path: String, file: String, message: String) async throws {
			try message.write(toFile: path + "/" + file, atomically: true, encoding: .utf8)
			try await git(at: path, "add", ".")
			try await git(at: path, "commit", "-m", message)
		}

		private func configure(_ path: String) async throws {
			try await git(at: path, "config", "user.email", "test@example.com")
			try await git(at: path, "config", "user.name", "Test")
			try await git(at: path, "config", "commit.gpgsign", "false")
		}

		@discardableResult
		func git(at path: String, _ arguments: String...) async throws -> String {
			let result = await ProcessRunner.runGit(arguments: arguments, at: path)
			guard result.success else {
				throw GitError.logFailed("git \(arguments.joined(separator: " ")): \(result.errorString)")
			}
			return result.outputString.trimmingCharacters(in: .whitespacesAndNewlines)
		}

		func remove() {
			try? FileManager.default.removeItem(atPath: root)
		}
	}

	@Test
	func startsAtOriginsLatestWhenAsked() async throws {
		let fixture = try await Fixture()
		defer { fixture.remove() }

		let folder = try await fixture.create(branch: "feature", startFromOrigin: true)

		let head = try await fixture.git(at: folder.path, "rev-parse", "HEAD")
		#expect(try await head == fixture.git(at: fixture.clone, "rev-parse", "origin/main"))
		#expect(try await head != fixture.git(at: fixture.clone, "rev-parse", "main"))
		// --no-track: pushing the branch must not go into main.
		let upstream = await ProcessRunner.runGit(arguments: ["rev-parse", "--abbrev-ref", "@{upstream}"], at: folder.path)
		#expect(!upstream.success)
	}

	@Test
	func startsAtTheLocalBranchOtherwise() async throws {
		let fixture = try await Fixture()
		defer { fixture.remove() }

		let folder = try await fixture.create(branch: "feature", startFromOrigin: false)

		#expect(try await fixture.git(at: folder.path, "rev-parse", "HEAD") == fixture.git(at: fixture.clone, "rev-parse", "main"))
	}

	@Test
	func fallsBackToTheLocalBranchWhenOriginHasNone() async throws {
		let fixture = try await Fixture()
		defer { fixture.remove() }
		try await fixture.git(at: fixture.clone, "branch", "local-only")
		try await fixture.commit(at: fixture.clone, file: "mine.txt", message: "mine")

		let folder = try await GitWorktreeCreator.createWorktree(
			branchName: "feature",
			baseBranch: "local-only",
			repositoryPath: fixture.clone,
			startFromOrigin: true,
			worktreeBasePath: fixture.worktrees
		)

		#expect(try await fixture.git(at: folder.path, "rev-parse", "HEAD") == fixture.git(at: fixture.clone, "rev-parse", "local-only"))
	}
}
