import Foundation
import ProcessExecution
import Testing

@testable import GitCore

@Suite("GitCommitActionHelper")
struct GitCommitActionHelperTests {

	// MARK: - Arguments

	private func commit(_ hash: String, parents: [String]) -> GitLogCommit {
		GitLogCommit(hash: hash, parents: parents, author: "A", date: Date(), refs: [], subject: "S")
	}

	@Test
	func cherryPickOfAPlainCommitNamesOnlyTheCommit() {
		let arguments = GitCommitActionHelper.arguments(for: .cherryPick, commit: commit("abc", parents: ["p1"]))
		#expect(arguments == ["cherry-pick", "abc"])
	}

	@Test
	func mergesAreTakenAgainstTheirFirstParent() {
		let merge = commit("abc", parents: ["p1", "p2"])
		#expect(GitCommitActionHelper.arguments(for: .cherryPick, commit: merge) == ["cherry-pick", "-m", "1", "abc"])
		#expect(GitCommitActionHelper.arguments(for: .revert, commit: merge) == ["revert", "--no-edit", "-m", "1", "abc"])
	}

	@Test
	func revertNeverOpensAnEditor() {
		let arguments = GitCommitActionHelper.arguments(for: .revert, commit: commit("abc", parents: ["p1"]))
		#expect(arguments == ["revert", "--no-edit", "abc"])
	}

	@Test(arguments: [
		("origin/main", "main"),
		("origin/feature/login", "feature/login"),
		("upstream/x", "x"),
	])
	func remoteBranchMapsToItsLocalNamesake(remote: String, local: String) {
		#expect(GitCommitActionHelper.localBranchName(forRemoteBranch: remote) == local)
	}

	@Test(arguments: ["main", "/main", "origin/"])
	func nameWithoutARemoteAndABranchHasNoLocalNamesake(name: String) {
		#expect(GitCommitActionHelper.localBranchName(forRemoteBranch: name) == nil)
	}

	// MARK: - Against a real repository

	/// A repository with `base.txt` committed on `main`, and a `side` branch whose one commit
	/// rewrites the file's only line.
	private struct Repository {
		let path: String

		init() async throws {
			path = NSTemporaryDirectory() + "GitCommitActionHelperTests-" + UUID().uuidString
			try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
			try await git("init", "--initial-branch=main")
			try await git("config", "user.email", "test@example.com")
			try await git("config", "user.name", "Test")
			try await git("config", "commit.gpgsign", "false")
			try write("base\n", to: "base.txt")
			try await git("add", ".")
			try await git("commit", "-m", "base")
		}

		func write(_ contents: String, to file: String) throws {
			try contents.write(toFile: path + "/" + file, atomically: true, encoding: .utf8)
		}

		@discardableResult
		func git(_ arguments: String...) async throws -> String {
			let result = await ProcessRunner.runGit(arguments: arguments, at: path)
			guard result.success else {
				throw GitError.logFailed("git \(arguments.joined(separator: " ")): \(result.errorString)")
			}
			return result.outputString.trimmingCharacters(in: .whitespacesAndNewlines)
		}

		/// Commits `contents` to `file` and returns the commit as the graph would list it.
		func commit(_ contents: String, to file: String, message: String) async throws -> GitLogCommit {
			try write(contents, to: file)
			try await git("add", ".")
			try await git("commit", "-m", message)
			let hash = try await git("rev-parse", "HEAD")
			let parent = try await git("rev-parse", "HEAD^")
			return GitLogCommit(hash: hash, parents: [parent], author: "Test", date: Date(), refs: [], subject: message)
		}

		func exists(_ ref: String) async -> Bool {
			await ProcessRunner.runGit(arguments: ["rev-parse", "--quiet", "--verify", ref], at: path).success
		}

		func remove() {
			try? FileManager.default.removeItem(atPath: path)
		}
	}

	@Test
	func cherryPickCommitsOntoTheCurrentBranch() async throws {
		let repository = try await Repository()
		defer { repository.remove() }

		try await repository.git("checkout", "-b", "side")
		let picked = try await repository.commit("new\n", to: "new.txt", message: "add new")
		try await repository.git("checkout", "main")

		let outcome = try await GitCommitActionHelper.apply(.cherryPick, commit: picked, at: repository.path)

		#expect(outcome == .committed)
		#expect(try await repository.git("log", "-1", "--format=%s") == "add new")
	}

	@Test
	func conflictsAreAnOutcomeAndLeaveTheCherryPickToResolve() async throws {
		let repository = try await Repository()
		defer { repository.remove() }

		try await repository.git("checkout", "-b", "side")
		let picked = try await repository.commit("side\n", to: "base.txt", message: "side edit")
		try await repository.git("checkout", "main")
		_ = try await repository.commit("main\n", to: "base.txt", message: "main edit")

		let outcome = try await GitCommitActionHelper.apply(.cherryPick, commit: picked, at: repository.path)

		#expect(outcome == .conflicts(["base.txt"]))
		#expect(await repository.exists("CHERRY_PICK_HEAD"))

		try await GitCommitActionHelper.abort(.cherryPick, at: repository.path)
		#expect(!(await repository.exists("CHERRY_PICK_HEAD")))
		#expect(try await repository.git("status", "--porcelain").isEmpty)
	}

	@Test
	func aCommitAlreadyOnTheBranchThrowsAndLeavesNothingInProgress() async throws {
		let repository = try await Repository()
		defer { repository.remove() }

		let onMain = try await repository.commit("more\n", to: "base.txt", message: "already here")

		await #expect(throws: GitError.self) {
			try await GitCommitActionHelper.apply(.cherryPick, commit: onMain, at: repository.path)
		}
		#expect(!(await repository.exists("CHERRY_PICK_HEAD")))
		#expect(try await repository.git("log", "-1", "--format=%s") == "already here")
	}

	@Test
	func revertAddsACommitUndoingTheChange() async throws {
		let repository = try await Repository()
		defer { repository.remove() }

		let reverted = try await repository.commit("changed\n", to: "base.txt", message: "change")

		let outcome = try await GitCommitActionHelper.apply(.revert, commit: reverted, at: repository.path)

		#expect(outcome == .committed)
		#expect(try String(contentsOfFile: repository.path + "/base.txt", encoding: .utf8) == "base\n")
		#expect(try await repository.git("log", "-1", "--format=%s") == "Revert \"change\"")
	}

	@Test
	func createBranchCanLeaveHeadWhereItIs() async throws {
		let repository = try await Repository()
		defer { repository.remove() }

		let base = try await repository.git("rev-parse", "HEAD")
		_ = try await repository.commit("later\n", to: "base.txt", message: "later")

		try await GitCommitActionHelper.createBranch(named: "from-base", at: base, checkout: false, repositoryPath: repository.path)
		#expect(try await repository.git("rev-parse", "from-base") == base)
		#expect(try await repository.git("branch", "--show-current") == "main")

		try await GitCommitActionHelper.createBranch(named: "switched", at: base, checkout: true, repositoryPath: repository.path)
		#expect(try await repository.git("branch", "--show-current") == "switched")
	}

	@Test
	func aBranchNameLikeAnOptionIsRefused() async throws {
		await #expect(throws: GitError.self) {
			try await GitCommitActionHelper.createBranch(named: "-D", at: "HEAD", checkout: false, repositoryPath: "/tmp")
		}
	}

	@Test
	func checkoutDetachedMovesHeadOffTheBranch() async throws {
		let repository = try await Repository()
		defer { repository.remove() }

		let base = try await repository.git("rev-parse", "HEAD")
		_ = try await repository.commit("later\n", to: "base.txt", message: "later")

		try await GitCommitActionHelper.checkoutDetached(hash: base, at: repository.path)

		#expect(try await repository.git("rev-parse", "HEAD") == base)
		#expect(try await repository.git("branch", "--show-current").isEmpty)
	}

	@Test
	func worktreeFromACommitStartsANewBranchThere() async throws {
		let repository = try await Repository()
		defer { repository.remove() }

		let base = try await repository.git("rev-parse", "HEAD")
		_ = try await repository.commit("later\n", to: "base.txt", message: "later")
		let basePath = "../" + (repository.path as NSString).lastPathComponent + "-worktrees"
		defer { try? FileManager.default.removeItem(atPath: (repository.path as NSString).appendingPathComponent(basePath)) }

		let folder = try await GitWorktreeCreator.createWorktree(
			branchName: "from-base",
			startPoint: base,
			repositoryPath: repository.path,
			worktreeBasePath: basePath
		)

		let worktreeHead = await ProcessRunner.runGit(arguments: ["rev-parse", "HEAD"], at: folder.path)
		#expect(worktreeHead.outputString.trimmingCharacters(in: .whitespacesAndNewlines) == base)
		#expect(folder.lastPathComponent == "from-base")
		#expect(GitDirectoryResolver.resolveMainRepositoryPath(at: folder.path).map(canonical) == canonical(repository.path))
	}

	private func canonical(_ path: String) -> String {
		URL(fileURLWithPath: path).resolvingSymlinksInPath().path
	}
}
