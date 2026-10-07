import Foundation
import ProcessExecution
import Testing

@testable import GitCore

@Suite("GitWorktreeCreator — a ref origin does not publish as a branch")
struct GitWorktreeCreatorForkTests {

	/// An `origin` with one commit on `main` and a PR head at `refs/pull/1/head` (a commit on top
	/// of it that no branch holds), and a clone of it — the setup of a PR from a fork.
	private struct Fixture {
		let root: String
		var origin: String { root + "/origin" }
		var clone: String { root + "/clone" }
		var worktrees: String { root + "/worktrees" }

		init() async throws {
			root = NSTemporaryDirectory() + "GitWorktreeCreatorForkTests-" + UUID().uuidString
			try FileManager.default.createDirectory(atPath: origin, withIntermediateDirectories: true)
			try await git(at: origin, "init", "--initial-branch=main")
			try await configure(origin)
			try await commit(at: origin, file: "base.txt", message: "base")
			try await pushPullRequest(message: "fork work")
			try await git(at: root, "clone", "origin", "clone")
			try await configure(clone)
		}

		/// Moves `refs/pull/1/head` on origin to a new commit on top of where it was (or of `main`).
		@discardableResult
		func pushPullRequest(message: String) async throws -> String {
			let start = try? await git(at: origin, "rev-parse", "--verify", "--quiet", "refs/pull/1/head")
			try await git(at: origin, "checkout", "--detach", start ?? "main")
			try await commit(at: origin, file: "fork.txt", message: message)
			let head = try await git(at: origin, "rev-parse", "HEAD")
			try await git(at: origin, "update-ref", "refs/pull/1/head", head)
			try await git(at: origin, "checkout", "main")
			return head
		}

		func create(candidates: [String]) async throws -> URL {
			try await GitWorktreeCreator.createWorktree(
				fetching: "refs/pull/1/head",
				branchCandidates: candidates,
				repositoryPath: clone,
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
	func checksOutTheHeadOnTheFirstFreeBranchWithNoUpstream() async throws {
		let fixture = try await Fixture()
		defer { fixture.remove() }

		let folder = try await fixture.create(candidates: ["feature", "someone/feature"])

		#expect(folder.lastPathComponent == "feature")
		#expect(try await fixture.git(at: folder.path, "branch", "--show-current") == "feature")
		#expect(try await fixture.git(at: folder.path, "log", "-1", "--format=%s") == "fork work")
		await #expect(throws: (any Error).self) {
			try await fixture.git(at: folder.path, "rev-parse", "--abbrev-ref", "@{upstream}")
		}
	}

	@Test
	func aLocalBranchHoldingOtherCommitsIsSkippedNotOverwritten() async throws {
		let fixture = try await Fixture()
		defer { fixture.remove() }
		let localMain = try await fixture.git(at: fixture.clone, "rev-parse", "main")

		let folder = try await fixture.create(candidates: ["main", "someone/main"])

		#expect(try await fixture.git(at: folder.path, "branch", "--show-current") == "someone/main")
		#expect(try await fixture.git(at: fixture.clone, "rev-parse", "main") == localMain)
	}

	@Test
	func anEarlierCheckoutOfThePullRequestIsFastForwarded() async throws {
		let fixture = try await Fixture()
		defer { fixture.remove() }
		let first = try await fixture.create(candidates: ["feature"])
		try await fixture.git(at: fixture.clone, "worktree", "remove", first.path)
		let newHead = try await fixture.pushPullRequest(message: "more fork work")

		let folder = try await fixture.create(candidates: ["feature"])

		#expect(try await fixture.git(at: folder.path, "rev-parse", "HEAD") == newHead)
	}

	@Test
	func anEarlierCheckoutWithLocalCommitsIsKeptAsIs() async throws {
		let fixture = try await Fixture()
		defer { fixture.remove() }
		let first = try await fixture.create(candidates: ["feature"])
		try await fixture.commit(at: first.path, file: "local.txt", message: "local work")
		try await fixture.git(at: fixture.clone, "worktree", "remove", first.path)

		let folder = try await fixture.create(candidates: ["feature"])

		#expect(try await fixture.git(at: folder.path, "log", "-1", "--format=%s") == "local work")
	}

	@Test
	func aBranchThePullRequestIsBasedOnIsNotFastForwarded() async throws {
		let fixture = try await Fixture()
		defer { fixture.remove() }
		// `main` is behind the PR head, as any PR's base is; it is not checked out anywhere.
		try await fixture.git(at: fixture.clone, "checkout", "--detach")
		let localMain = try await fixture.git(at: fixture.clone, "rev-parse", "main")

		let folder = try await fixture.create(candidates: ["main", "someone/main"])

		#expect(try await fixture.git(at: folder.path, "branch", "--show-current") == "someone/main")
		#expect(try await fixture.git(at: fixture.clone, "rev-parse", "main") == localMain)
	}

	@Test
	func failsWhenEveryCandidateHoldsOtherCommits() async throws {
		let fixture = try await Fixture()
		defer { fixture.remove() }

		await #expect(throws: GitError.self) {
			try await fixture.create(candidates: ["main"])
		}
	}
}
