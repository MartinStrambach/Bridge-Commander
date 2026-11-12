import Foundation
import ProcessExecution
import Testing

@testable import GitCore

@Suite("GitStatusDetector")
struct GitStatusDetectorTests {

	/// A repository on `main` with one commit, which `refs/remotes/origin/main` points at as if
	/// it had been pushed. The remote's URL is never contacted; the tracking ref is written by hand.
	private struct Repository {
		let path: String

		init(withRemote: Bool = true) async throws {
			path = NSTemporaryDirectory() + "GitStatusDetectorTests-" + UUID().uuidString
			try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
			try await git("init", "--initial-branch=main")
			try await git("config", "user.email", "test@example.com")
			try await git("config", "user.name", "Test")
			try await git("config", "commit.gpgsign", "false")
			try await commit("base")
			if withRemote {
				try await git("remote", "add", "origin", "https://example.invalid/repo.git")
				try await git("update-ref", "refs/remotes/origin/main", "HEAD")
			}
		}

		@discardableResult
		func git(_ arguments: String...) async throws -> String {
			let result = await ProcessRunner.runGit(arguments: arguments, at: path)
			guard result.success else {
				throw GitError.logFailed("git \(arguments.joined(separator: " ")): \(result.errorString)")
			}
			return result.outputString.trimmingCharacters(in: .whitespacesAndNewlines)
		}

		func commit(_ message: String) async throws {
			try await git("commit", "--allow-empty", "-m", message)
		}

		func remove() {
			try? FileManager.default.removeItem(atPath: path)
		}
	}

	@Test
	func branchWithoutUpstreamCountsCommitsOnNoRemote() async throws {
		let repository = try await Repository()
		defer { repository.remove() }

		try await repository.git("checkout", "-b", "feature")
		try await repository.commit("one")
		try await repository.commit("two")

		let status = await GitStatusDetector.getStatus(at: repository.path)

		#expect(!status.hasRemoteBranch)
		#expect(status.unpushedCount == 2)
	}

	@Test
	func branchWithoutUpstreamAndNoNewCommitsHasNothingToPush() async throws {
		let repository = try await Repository()
		defer { repository.remove() }

		try await repository.git("checkout", "-b", "feature")

		let status = await GitStatusDetector.getStatus(at: repository.path)

		#expect(status.unpushedCount == 0)
	}

	@Test
	func repositoryWithNoRemotesCountsNothing() async throws {
		let repository = try await Repository(withRemote: false)
		defer { repository.remove() }

		try await repository.commit("one")

		let status = await GitStatusDetector.getStatus(at: repository.path)

		#expect(status.unpushedCount == 0)
	}

	@Test
	func branchWithUpstreamStillCountsAgainstIt() async throws {
		let repository = try await Repository()
		defer { repository.remove() }

		try await repository.git("branch", "--set-upstream-to=origin/main")
		try await repository.commit("one")

		let status = await GitStatusDetector.getStatus(at: repository.path)

		#expect(status.hasRemoteBranch)
		#expect(status.unpushedCount == 1)
	}

	@Test
	func detachedHeadIsOnNoBranch() async throws {
		let repository = try await Repository()
		defer { repository.remove() }

		try await repository.commit("one")
		let head = try await repository.git("rev-parse", "HEAD")
		try await repository.git("checkout", "--detach")

		let status = await GitStatusDetector.getStatus(at: repository.path)

		#expect(status.isDetached)
		#expect(status.branch == nil)
		#expect(status.headOid == head)
	}

	/// Both backends: the merge one (the default) keeps its state in `rebase-merge`, `--apply` in
	/// `rebase-apply`.
	@Test(arguments: [["rebase"], ["rebase", "--apply"]])
	func rebaseStaysOnTheBranchBeingRebased(rebase: [String]) async throws {
		let repository = try await Repository()
		defer { repository.remove() }

		// Both branches change the same file, so the rebase stops on a conflict with HEAD detached.
		try await repository.git("checkout", "-b", "feature")
		try await repository.git("branch", "--set-upstream-to=origin/main")
		try "feature".write(toFile: repository.path + "/file", atomically: true, encoding: .utf8)
		try await repository.git("add", "file")
		try await repository.commit("feature")
		try await repository.git("checkout", "main")
		try "main".write(toFile: repository.path + "/file", atomically: true, encoding: .utf8)
		try await repository.git("add", "file")
		try await repository.commit("main")
		try await repository.git("checkout", "feature")
		_ = await ProcessRunner.runGit(arguments: rebase + ["main"], at: repository.path)

		let status = await GitStatusDetector.getStatus(at: repository.path)

		#expect(GitMergeDetector.isGitOperationInProgress(at: repository.path))
		#expect(!status.isDetached)
		#expect(status.branch == "feature")
		#expect(status.hasRemoteBranch)
	}

	@Test
	func parsingDetachedHead() {
		let status = GitPorcelainStatus(parsing: "# branch.oid abc\n# branch.head (detached)\n")
		#expect(status.isDetached)
		#expect(status.branch == nil)
		#expect(status.headOid == "abc")
	}

	@Test
	func parsingUnbornBranchHasNoHead() {
		let status = GitPorcelainStatus(parsing: "# branch.oid (initial)\n# branch.head main\n")
		#expect(!status.isDetached)
		#expect(status.branch == "main")
		#expect(status.headOid == nil)
	}

	@Test
	func parsingAloneLeavesNoUpstreamAtZero() {
		let status = GitPorcelainStatus(parsing: "# branch.oid abc\n# branch.head feature\n")
		#expect(status.branch == "feature")
		#expect(!status.hasRemoteBranch)
		#expect(status.unpushedCount == 0)
	}
}
