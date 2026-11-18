import Foundation
import ProcessExecution
import Testing

@testable import GitCore

@Suite("GitPushHelper — pushing a rewritten branch")
struct GitPushHelperTests {

	/// A bare `origin` with `main`, and a clone whose `feature` branch is pushed and tracked.
	private struct Fixture {
		let root: String
		var origin: String { root + "/origin.git" }
		var clone: String { root + "/clone" }
		var other: String { root + "/other" }

		init() async throws {
			root = NSTemporaryDirectory() + "GitPushHelperTests-" + UUID().uuidString
			try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
			try await git(at: root, "init", "--bare", "--initial-branch=main", "origin.git")
			try await git(at: root, "clone", "origin.git", "clone")
			try await configure(clone)
			try await commit(at: clone, file: "base.txt", message: "base")
			try await git(at: clone, "push", "origin", "HEAD:main")
			try await git(at: clone, "checkout", "-b", "feature")
			try await commit(at: clone, file: "feature.txt", message: "feature")
			try await git(at: clone, "push", "-u", "origin", "feature")
		}

		/// `main` moves on in `origin` and `feature` is rebased onto it, so `origin/feature` keeps
		/// the pre-rebase commit.
		func rebaseFeatureOntoNewerMain() async throws {
			try await git(at: clone, "checkout", "main")
			try await commit(at: clone, file: "main.txt", message: "main moved on")
			try await git(at: clone, "push", "origin", "main")
			try await git(at: clone, "checkout", "feature")
			try await git(at: clone, "rebase", "main")
		}

		/// Someone else pushes to `feature`; the clone fetches it but does not build on it.
		func otherPushesToFeatureAndCloneFetches() async throws {
			try await git(at: root, "clone", "--branch", "feature", "origin.git", "other")
			try await configure(other)
			try await commit(at: other, file: "theirs.txt", message: "theirs")
			try await git(at: other, "push")
			try await commit(at: clone, file: "mine.txt", message: "mine")
			try await git(at: clone, "fetch")
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

	@Test("after a rebase a plain push is rejected as non-fast-forward and a lease push replaces the branch")
	func rebasedBranchNeedsForcePush() async throws {
		let fixture = try await Fixture()
		defer { fixture.remove() }
		try await fixture.rebaseFeatureOntoNewerMain()

		let error = await #expect(throws: GitError.self) {
			try await GitPushHelper.push(at: fixture.clone)
		}
		let rejected = try #require(error?.nonFastForwardRejection)
		#expect(rejected == GitRejectedPush(localBranch: "feature", remoteBranch: "feature"))

		_ = try await GitPushHelper.push(at: fixture.clone, mode: .forceWithLease(rejected))
		#expect(
			try await fixture.git(at: fixture.origin, "rev-parse", "feature")
				== fixture.git(at: fixture.clone, "rev-parse", "HEAD")
		)
	}

	@Test("a lease push pushes the rejected branch, not whatever HEAD has moved to since")
	func leasePushNamesItsBranch() async throws {
		let fixture = try await Fixture()
		defer { fixture.remove() }
		try await fixture.rebaseFeatureOntoNewerMain()
		let rebased = try await fixture.git(at: fixture.clone, "rev-parse", "feature")
		// Something (a terminal tab, Claude Code) switches branch while the alert is open, and
		// that branch has a commit of its own.
		try await fixture.git(at: fixture.clone, "checkout", "main")
		try await fixture.commit(at: fixture.clone, file: "local.txt", message: "not to be pushed")
		let originMain = try await fixture.git(at: fixture.origin, "rev-parse", "main")

		let rejected = GitRejectedPush(localBranch: "feature", remoteBranch: "feature")
		_ = try await GitPushHelper.push(at: fixture.clone, mode: .forceWithLease(rejected))

		#expect(try await fixture.git(at: fixture.origin, "rev-parse", "feature") == rebased)
		#expect(try await fixture.git(at: fixture.origin, "rev-parse", "main") == originMain)
	}

	@Test("a lease push refuses to drop commits that were fetched but never built on")
	func leasePushKeepsFetchedForeignCommits() async throws {
		let fixture = try await Fixture()
		defer { fixture.remove() }
		try await fixture.otherPushesToFeatureAndCloneFetches()
		let theirs = try await fixture.git(at: fixture.origin, "rev-parse", "feature")

		// The fetch satisfies `--force-with-lease` alone; `--force-if-includes` is what refuses.
		let rejected = GitRejectedPush(localBranch: "feature", remoteBranch: "feature")
		await #expect(throws: GitError.self) {
			try await GitPushHelper.push(at: fixture.clone, mode: .forceWithLease(rejected))
		}
		#expect(try await fixture.git(at: fixture.origin, "rev-parse", "feature") == theirs)
	}
}
