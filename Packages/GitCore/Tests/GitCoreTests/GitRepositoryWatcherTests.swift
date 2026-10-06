import Foundation
import ProcessExecution
import Synchronization
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

	@Test(arguments: [
		"HEAD", "index", "MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "rebase-merge/done", "config.worktree",
	])
	func perWorktreeStateRefreshesOnlyItsOwnWorktree(entry: String) {
		#expect(classify(FileSystemEvent(path: "/r/.git/" + entry)).kinds == ["/r": .status])
		#expect(classify(FileSystemEvent(path: "/r/.git/worktrees/feature/" + entry)).kinds == ["/r-feature": .status])
	}

	@Test(arguments: [
		"/r/.git/refs/heads/main", "/r/.git/refs/remotes/origin/feature", "/r/.git/packed-refs", "/r/.git/config",
	])
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
		// A reftable update writes its tables first; only `tables.list` commits it.
		"/r/.git/reftable/0x000000000001-0x000000000004-584e24ab.ref",
		"/r/.git/reftable/tables.list.lock",
		"/r/.git/worktrees/feature/reftable/0x000000000001-0x000000000004-746c435d.ref",
	])
	func gitDirectoryChurnIsIgnored(path: String) {
		#expect(classify(FileSystemEvent(path: path, isCreatedOrRemoved: true)) == .init())
	}

	@Test
	func sharedReftableRefreshesEveryWorktreeAndItsStash() {
		#expect(classify(FileSystemEvent(path: "/r/.git/reftable/tables.list")).kinds == [
			"/r": [.status, .stash],
			"/r-feature": [.status, .stash],
		])
	}

	@Test
	func linkedWorktreeReftableRefreshesOnlyThatWorktree() {
		#expect(classify(FileSystemEvent(path: "/r/.git/worktrees/feature/reftable/tables.list")).kinds == [
			"/r-feature": .status,
		])
	}

	@Test
	func addingOrRemovingAWorktreeAsksForTheListAgain() {
		let added = classify(FileSystemEvent(path: "/r/.git/worktrees/other", isCreatedOrRemoved: true))
		#expect(added.kinds == ["/r": .worktreeList])
	}

	@Test
	func movingAWorktreeAsksForTheListAgain() {
		// `git worktree move` writes the new path here and nothing else in the git directory.
		let moved = classify(FileSystemEvent(path: "/r/.git/worktrees/feature/gitdir"))
		#expect(moved.kinds == ["/r": .worktreeList])
	}

	@Test
	func modifyingAWorktreeEntryIsNotAListChange() {
		#expect(classify(FileSystemEvent(path: "/r/.git/worktrees/feature")) == .init())
		#expect(classify(FileSystemEvent(path: "/r/.git/worktrees/feature/commondir")) == .init())
	}

	@Test
	func configInsideAWorktreeEntryIsNotTheSharedConfig() {
		#expect(classify(FileSystemEvent(path: "/r/.git/worktrees/feature/config")) == .init())
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

	@Test(arguments: [
		"/r/.DS_Store",
		"/r/Sources/.DS_Store",
		"/r-feature/.git",
		"/r/vendor/lib/.git/HEAD",
		"/elsewhere/x",
	])
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

		/// - Parameters:
		///   - directory: Where to create it; a new temporary directory when nil.
		///   - refFormat: `git init --ref-format`, git's default when nil.
		init(at directory: String? = nil, refFormat: String? = nil) async throws {
			let directory = directory ?? Self.makeDirectory()
			path = GitWatchTarget.canonicalPath(directory)
			if let refFormat {
				try await git("init", "--initial-branch=main", "--ref-format=\(refFormat)")
			}
			else {
				try await git("init", "--initial-branch=main")
			}
			try await git("config", "user.email", "test@example.com")
			try await git("config", "user.name", "Test")
			try await git("config", "commit.gpgsign", "false")
			try write("build/\n*.o\n", to: ".gitignore")
			try write("tracked\n", to: "tracked.txt")
			try write("tracked\n", to: "kept.o")
			try await git("add", "-f", ".")
			try await git("commit", "-m", "base")
		}

		static func makeDirectory() -> String {
			let directory = NSTemporaryDirectory() + "GitRepositoryWatcherTests-" + UUID().uuidString
			try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
			return directory
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

		let changes = try await firstChange(watching: [repository.path]) {
			_ = await ProcessRunner.runGit(arguments: ["checkout", "-b", "feature"], at: repository.path)
		}
		#expect(changes.map(\.repositoryPath) == [repository.path])
	}

	@Test
	func fetchInAReftableRepositoryIsReported() async throws {
		let repository = try await Repository(refFormat: "reftable")
		defer { repository.remove() }

		// What a fetch does to the upstream, without a remote. It writes no index and, in a
		// reftable repository, nothing under `refs/` — only the reftable update can report it.
		let changes = try await firstChange(watching: [repository.path]) {
			_ = await ProcessRunner.runGit(arguments: ["update-ref", "refs/remotes/origin/main", "HEAD"], at: repository.path)
		}
		#expect(changes.map(\.repositoryPath) == [repository.path])
	}

	@Test
	func settingAnUpstreamInATerminalIsReported() async throws {
		let repository = try await Repository()
		defer { repository.remove() }
		try await repository.git("remote", "add", "origin", "/nonexistent")
		try await repository.git("update-ref", "refs/remotes/origin/main", "HEAD")

		// Writes only `.git/config`, yet changes what `git status` counts against.
		let changes = try await firstChange(watching: [repository.path]) {
			_ = await ProcessRunner.runGit(arguments: ["branch", "-u", "origin/main"], at: repository.path)
		}
		#expect(changes.map(\.repositoryPath) == [repository.path])
	}

	@Test
	func aPathThatBecomesARepositoryLaterIsWatchedOnceItDoes() async throws {
		let directory = GitWatchTarget.canonicalPath(Repository.makeDirectory())
		defer { try? FileManager.default.removeItem(atPath: directory) }

		// Nothing to watch at first, so the stream cannot even start; it must keep trying.
		let changes = try await firstChange(watching: [directory], retryInterval: .milliseconds(200)) {
			let repository = try? await Repository(at: directory)
			// Long enough for a retry to pick the repository up, then a change it must report.
			try? await Task.sleep(for: .milliseconds(1000))
			_ = try? await repository?.git("checkout", "-b", "feature")
		}
		#expect(changes.map(\.repositoryPath) == [directory])
	}

	@Test
	func aRepositoryThatAppearsLaterJoinsAWatchAlreadyRunning() async throws {
		let watched = try await Repository()
		let directory = GitWatchTarget.canonicalPath(Repository.makeDirectory())
		defer {
			watched.remove()
			try? FileManager.default.removeItem(atPath: directory)
		}

		let changes = try await firstChange(watching: [watched.path, directory], retryInterval: .milliseconds(200)) {
			let repository = try? await Repository(at: directory)
			try? await Task.sleep(for: .milliseconds(1000))
			_ = try? await repository?.git("checkout", "-b", "feature")
		}
		#expect(changes.contains { $0.repositoryPath == directory })
	}

	// MARK: - Working tree filtering

	@Test
	func editOutsideIgnoredFoldersRefreshesStatus() async throws {
		let repository = try await Repository()
		defer { repository.remove() }
		let target = try #require(GitWatchTarget(repositoryPath: repository.path))

		let changes = await GitRepositoryWatcher.changes(
			in: [
				FileSystemEvent(path: repository.path + "/build/out.o"),
				FileSystemEvent(path: repository.path + "/Sources/New.swift"),
			],
			targets: [target]
		)
		#expect(changes == [GitRepositoryChange(repositoryPath: repository.path, kinds: .status)])
	}

	@Test
	func buildOutputAloneChangesNothing() async throws {
		let repository = try await Repository()
		defer { repository.remove() }
		let target = try #require(GitWatchTarget(repositoryPath: repository.path))

		let changes = await GitRepositoryWatcher.changes(
			in: [
				FileSystemEvent(path: repository.path + "/build/x/y.o"),
				FileSystemEvent(path: repository.path + "/main.o"),
			],
			targets: [target]
		)
		#expect(changes.isEmpty)
	}

	@Test
	func gitStateChangeNeedsNoIgnoreCheck() async {
		// Not a repository at all: `check-ignore` would fail and count every path as changed, so
		// an empty working-tree list here proves the status change was decided without it.
		let target = GitWatchTarget(
			repositoryPath: "/nowhere",
			workTree: "/nowhere",
			gitDirectory: "/nowhere/.git",
			commonGitDirectory: "/nowhere/.git"
		)
		let changes = await GitRepositoryWatcher.changes(
			in: [FileSystemEvent(path: "/nowhere/.git/HEAD"), FileSystemEvent(path: "/nowhere/build/a")],
			targets: [target]
		)
		#expect(changes == [GitRepositoryChange(repositoryPath: "/nowhere", kinds: .status)])
	}

	@Test
	func pathsCountAsChangedWhenGitCannotAnswer() async throws {
		let directory = NSTemporaryDirectory() + "GitRepositoryWatcherTests-" + UUID().uuidString
		try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(atPath: directory) }

		#expect(await GitRepositoryWatcher.containsUnignoredPath(["build/a"], inWorkTree: directory))
	}

	// MARK: - Linked worktrees

	@Test
	func linkedWorktreeResolvesItsOwnAndTheSharedGitDirectory() async throws {
		let repository = try await Repository()
		let worktree = repository.path + "-feature"
		defer {
			repository.remove()
			try? FileManager.default.removeItem(atPath: worktree)
		}
		try await repository.git("worktree", "add", "-b", "feature", worktree)

		let target = try #require(GitWatchTarget(repositoryPath: worktree))
		#expect(target.workTree == worktree)
		#expect(target.gitDirectory == repository.path + "/.git/worktrees/" + (worktree as NSString).lastPathComponent)
		#expect(target.commonGitDirectory == repository.path + "/.git")
	}

	@Test
	func checkoutInALinkedWorktreeIsReportedForThatWorktree() async throws {
		let repository = try await Repository()
		let worktree = repository.path + "-feature"
		defer {
			repository.remove()
			try? FileManager.default.removeItem(atPath: worktree)
		}
		try await repository.git("worktree", "add", "-b", "feature", worktree)
		// An existing branch: `checkout -b` would also create a ref, which is shared and rightly
		// refreshes every worktree of the repository.
		try await repository.git("branch", "other")

		let changes = try await firstChange(watching: [repository.path, worktree]) {
			_ = await ProcessRunner.runGit(arguments: ["checkout", "other"], at: worktree)
		}
		#expect(changes.contains(GitRepositoryChange(repositoryPath: worktree, kinds: .status)))
		// Its HEAD lives in the worktree's own git directory, not in the main checkout's.
		#expect(!changes.contains { $0.repositoryPath == repository.path })
	}

	@Test
	func worktreeAddedInATerminalIsReported() async throws {
		let repository = try await Repository()
		let worktree = repository.path + "-added"
		defer {
			repository.remove()
			try? FileManager.default.removeItem(atPath: worktree)
		}

		let changes = try await firstChange(watching: [repository.path], matching: .worktreeList) {
			_ = await ProcessRunner.runGit(arguments: ["worktree", "add", "-b", "added", worktree], at: repository.path)
		}
		#expect(changes.contains { $0.repositoryPath == repository.path && $0.kinds.contains(.worktreeList) })
	}

	@Test
	func worktreeMovedInATerminalIsReported() async throws {
		let repository = try await Repository()
		let worktree = repository.path + "-feature"
		let moved = repository.path + "-moved"
		defer {
			repository.remove()
			try? FileManager.default.removeItem(atPath: worktree)
			try? FileManager.default.removeItem(atPath: moved)
		}
		try await repository.git("worktree", "add", "-b", "feature", worktree)

		let changes = try await firstChange(watching: [repository.path, worktree], matching: .worktreeList) {
			_ = await ProcessRunner.runGit(arguments: ["worktree", "move", worktree, moved], at: repository.path)
		}
		#expect(changes.contains { $0.repositoryPath == repository.path && $0.kinds.contains(.worktreeList) })
	}

	/// The first batch from a live watch that has a change of `kind`, after `action` runs.
	private func firstChange(
		watching repositoryPaths: [String],
		matching kind: GitRepositoryChange.Kind = .status,
		retryInterval: Duration = GitRepositoryWatcher.retryInterval,
		after action: @escaping @Sendable () async -> Void
	) async throws -> [GitRepositoryChange] {
		let stream = GitRepositoryWatcher.changes(repositoryPaths: repositoryPaths, retryInterval: retryInterval)
		let isActing = Atomic(false)
		let first = Task {
			for await changes in stream
				where isActing.load(ordering: .sequentiallyConsistent) && changes.contains(where: { $0.kinds.contains(kind) })
			{
				return changes
			}
			return []
		}
		// `kFSEventStreamEventIdSinceNow` still delivers events fseventsd had not yet flushed when
		// the stream started — here, the test's own setup. Let those arrive and drop them.
		try await Task.sleep(for: .milliseconds(1000))
		isActing.store(true, ordering: .sequentiallyConsistent)
		await action()

		let timeout = Task {
			try await Task.sleep(for: .seconds(10))
			first.cancel()
		}
		defer { timeout.cancel() }
		return await first.value
	}
}
