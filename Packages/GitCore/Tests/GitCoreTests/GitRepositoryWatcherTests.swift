import Foundation
import ProcessExecution
import Testing

@testable import GitCore

@Suite("GitRepositoryWatcher")
struct GitRepositoryWatcherTests {

	// MARK: - Classification

	/// `/r` is a main checkout with a linked worktree at `/r-feature`.
	private let main = GitWatchTarget(
		repositoryPath: "/r",
		workTree: "/r",
		gitDirectory: "/r/.git",
		commonGitDirectory: "/r/.git"
	)
	private let feature = GitWatchTarget(
		repositoryPath: "/r-feature",
		workTree: "/r-feature",
		gitDirectory: "/r/.git/worktrees/feature",
		commonGitDirectory: "/r/.git"
	)

	private func classify(_ events: FileSystemEvent...) -> GitChangeClassifier.Classification {
		GitChangeClassifier.classify(events, targets: [main, feature])
	}

	@Test(arguments: ["HEAD", "index", "MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "rebase-merge/done"])
	func perWorktreeStateRefreshesOnlyItsOwnWorktree(entry: String) {
		#expect(classify(FileSystemEvent(path: "/r/.git/" + entry)).kinds == ["/r": .status])
		#expect(classify(FileSystemEvent(path: "/r/.git/worktrees/feature/" + entry)).kinds == ["/r-feature": .status])
	}

	@Test(arguments: ["/r/.git/refs/heads/main", "/r/.git/refs/remotes/origin/feature", "/r/.git/packed-refs"])
	func sharedRefsRefreshEveryWorktree(path: String) {
		#expect(classify(FileSystemEvent(path: path)).kinds == ["/r": .status, "/r-feature": .status])
	}

	@Test
	func stashRefIsReportedAsAStashChange() {
		#expect(classify(FileSystemEvent(path: "/r/.git/refs/stash")).kinds == ["/r": .stash, "/r-feature": .stash])
	}

	@Test(arguments: [
		"/r/.git/HEAD.lock",
		"/r/.git/index.lock",
		"/r/.git/refs/heads/main.lock",
		"/r/.git/objects/ab/cdef",
		"/r/.git/logs/HEAD",
		"/r/.git/FETCH_HEAD",
		"/r/.git/ORIG_HEAD",
		"/r/.git/worktrees/feature/logs/HEAD",
	])
	func gitDirectoryChurnIsIgnored(path: String) {
		#expect(classify(FileSystemEvent(path: path, isCreatedOrRemoved: true)) == .init())
	}

	@Test
	func addingOrRemovingAWorktreeAsksForTheListAgain() {
		let added = classify(FileSystemEvent(path: "/r/.git/worktrees/other", isCreatedOrRemoved: true))
		#expect(added.kinds == ["/r": .worktreeList])
	}

	@Test
	func modifyingAWorktreeEntryIsNotAListChange() {
		#expect(classify(FileSystemEvent(path: "/r/.git/worktrees/feature")) == .init())
	}

	@Test
	func workingTreeEditsGoToTheInnermostWorkTree() {
		let nested = GitWatchTarget(
			repositoryPath: "/r/.worktrees/nested",
			workTree: "/r/.worktrees/nested",
			gitDirectory: "/r/.git/worktrees/nested",
			commonGitDirectory: "/r/.git"
		)
		let result = GitChangeClassifier.classify(
			[
				FileSystemEvent(path: "/r/Sources/App.swift"),
				FileSystemEvent(path: "/r/.worktrees/nested/Sources/App.swift"),
				FileSystemEvent(path: "/r-feature/README.md"),
			],
			targets: [main, feature, nested]
		)
		#expect(result.kinds.isEmpty)
		#expect(result.workingTreePaths == [
			"/r": ["Sources/App.swift"],
			"/r/.worktrees/nested": ["Sources/App.swift"],
			"/r-feature": ["README.md"],
		])
	}

	@Test(arguments: ["/r/.DS_Store", "/r/Sources/.DS_Store", "/r-feature/.git", "/r/vendor/lib/.git/HEAD", "/elsewhere/x"])
	func pathsGitStatusNeverReportsAreDropped(path: String) {
		#expect(classify(FileSystemEvent(path: path)) == .init())
	}

	@Test
	func droppedEventsRefreshEverythingUnderThePath() {
		#expect(classify(FileSystemEvent(path: "/r-feature", mustRescan: true)).kinds == ["/r-feature": .status])
		#expect(classify(FileSystemEvent(path: "/", mustRescan: true)).kinds == ["/r": .status, "/r-feature": .status])
	}

	@Test
	func watchRootsSkipDirectoriesAnotherRootAlreadyCovers() {
		#expect(GitChangeClassifier.watchRoots(for: [main, feature]) == ["/r", "/r-feature"])
	}

	// MARK: - Against a real repository

	/// A repository with `tracked.txt` committed and `build/` ignored.
	private struct Repository {
		let path: String

		init() async throws {
			let directory = NSTemporaryDirectory() + "GitRepositoryWatcherTests-" + UUID().uuidString
			try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
			path = GitWatchTarget.canonicalPath(directory)
			try await git("init", "--initial-branch=main")
			try await git("config", "user.email", "test@example.com")
			try await git("config", "user.name", "Test")
			try await git("config", "commit.gpgsign", "false")
			try write("build/\n*.o\n", to: ".gitignore")
			try write("tracked\n", to: "tracked.txt")
			try write("tracked\n", to: "kept.o")
			try await git("add", "-f", ".")
			try await git("commit", "-m", "base")
		}

		func write(_ contents: String, to file: String) throws {
			let url = URL(fileURLWithPath: path + "/" + file)
			try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
			try contents.write(to: url, atomically: true, encoding: .utf8)
		}

		@discardableResult
		func git(_ arguments: String...) async throws -> String {
			let result = await ProcessRunner.runGit(arguments: arguments, at: path)
			guard result.success else {
				throw GitError.logFailed("git \(arguments.joined(separator: " ")): \(result.errorString)")
			}
			return result.outputString
		}

		func remove() {
			try? FileManager.default.removeItem(atPath: path)
		}
	}

	@Test
	func ignoredBuildOutputDoesNotCount() async throws {
		let repository = try await Repository()
		defer { repository.remove() }

		let ignored = ["build/x/y.o", "build/a", "main.o"]
		#expect(await GitRepositoryWatcher.containsUnignoredPath(ignored, inWorkTree: repository.path) == false)
	}

	@Test(arguments: [
		["build/a", "Sources/New.swift"],
		["tracked.txt"],
		// Tracked, even though `*.o` matches it.
		["kept.o"],
		["-starts-with-a-dash"],
	])
	func anyPathStatusWouldReportCounts(paths: [String]) async throws {
		let repository = try await Repository()
		defer { repository.remove() }

		#expect(await GitRepositoryWatcher.containsUnignoredPath(paths, inWorkTree: repository.path))
	}

	@Test
	func statusLeavesTheIndexAlone() async throws {
		let repository = try await Repository()
		defer { repository.remove() }

		// Touch a tracked file so a plain `git status` would have stat data to write back.
		try repository.write("tracked\n", to: "tracked.txt")
		let index = repository.path + "/.git/index"
		let before = try FileManager.default.attributesOfItem(atPath: index)[.modificationDate] as? Date
		try await Task.sleep(for: .milliseconds(1100))
		_ = await GitStatusDetector.getStatus(at: repository.path)
		let after = try FileManager.default.attributesOfItem(atPath: index)[.modificationDate] as? Date
		#expect(before == after)
	}

	@Test
	func checkoutInATerminalIsReported() async throws {
		let repository = try await Repository()
		defer { repository.remove() }

		let stream = GitRepositoryWatcher.changes(repositoryPaths: [repository.path])
		let first = Task {
			for await changes in stream where changes.contains(where: { $0.kinds.contains(.status) }) {
				return changes
			}
			return []
		}
		// FSEvents only reports what happens after the stream starts.
		try await Task.sleep(for: .milliseconds(500))
		try await repository.git("checkout", "-b", "feature")

		let timeout = Task {
			try await Task.sleep(for: .seconds(10))
			first.cancel()
		}
		let changes = await first.value
		timeout.cancel()
		#expect(changes.map(\.repositoryPath) == [repository.path])
	}
}
