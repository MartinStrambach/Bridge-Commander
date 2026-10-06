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
	func parsingAloneLeavesNoUpstreamAtZero() {
		let status = GitPorcelainStatus(parsing: "# branch.oid abc\n# branch.head feature\n")
		#expect(status.branch == "feature")
		#expect(!status.hasRemoteBranch)
		#expect(status.unpushedCount == 0)
	}
}
