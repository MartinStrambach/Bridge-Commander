import Foundation
import ProcessExecution
import Testing

@testable import GitCore

@Suite("RepositoryLocation")
struct RepositoryLocationTests {
	// MARK: - Locating

	@Test
	func aFolderWithoutABookmarkGetsOne() throws {
		let folder = try makeFolder()
		defer { remove(folder) }

		guard case let .present(bookmark) = RepositoryBookmark.locate(path: folder, bookmark: nil) else {
			Issue.record("expected the folder to be present")
			return
		}
		#expect(bookmark != nil)
	}

	@Test
	func aFolderWithItsOwnBookmarkKeepsIt() throws {
		let folder = try makeFolder()
		defer { remove(folder) }
		let bookmark = try #require(RepositoryBookmark.make(path: folder))

		#expect(RepositoryBookmark.locate(path: folder, bookmark: bookmark) == .present(bookmark: nil))
	}

	@Test
	func aRenamedFolderIsFollowed() throws {
		let folder = try makeFolder()
		let renamed = folder + "-renamed"
		defer {
			remove(folder)
			remove(renamed)
		}
		let bookmark = try #require(RepositoryBookmark.make(path: folder))
		try FileManager.default.moveItem(atPath: folder, toPath: renamed)

		guard case let .moved(path, newBookmark) = RepositoryBookmark.locate(path: folder, bookmark: bookmark) else {
			Issue.record("expected the folder to be found at its new path")
			return
		}
		#expect(GitWatchTarget.canonicalPath(path) == GitWatchTarget.canonicalPath(renamed))
		#expect(newBookmark != nil)
	}

	@Test
	func aFolderThatTookTheOldNameIsTrackedFromThenOn() throws {
		// Renamed out of the way, and another folder created under the old name: the path wins,
		// and the bookmark is replaced so a later rename of the new folder is followed, not the old one.
		let folder = try makeFolder()
		let renamed = folder + "-renamed"
		defer {
			remove(folder)
			remove(renamed)
		}
		let bookmark = try #require(RepositoryBookmark.make(path: folder))
		try FileManager.default.moveItem(atPath: folder, toPath: renamed)
		try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: false)

		guard case let .present(newBookmark) = RepositoryBookmark.locate(path: folder, bookmark: bookmark) else {
			Issue.record("expected the folder at the old path to be present")
			return
		}
		#expect(newBookmark != nil)
	}

	@Test
	func aDeletedFolderIsMissing() throws {
		let folder = try makeFolder()
		let bookmark = try #require(RepositoryBookmark.make(path: folder))
		remove(folder)

		#expect(RepositoryBookmark.locate(path: folder, bookmark: bookmark) == .missing)
		#expect(RepositoryBookmark.locate(path: folder, bookmark: nil) == .missing)
	}

	@Test(arguments: [
		("/Users/me/.Trash/repo", true),
		("/Volumes/Disk/.Trashes/501/repo", true),
		("/Users/me/Documents/repo", false),
		("/Users/me/Documents/.Trashy/repo", false),
	])
	func trashIsRecognized(path: String, isInTrash: Bool) {
		#expect(RepositoryBookmark.isInTrash(path) == isInTrash)
	}

	// MARK: - Worktree repair

	@Test(arguments: [
		("/a/main/nested/wt", "/a/main", "/a/moved", "/a/moved/nested/wt"),
		("/private/var/x/main/wt", "/var/x/main", "/var/x/moved", "/var/x/moved/wt"),
		("/a/main-other/wt", "/a/main", "/a/moved", nil),
		("/a/main", "/a/main", "/a/moved", nil),
	] as [(String, String, String, String?)])
	func worktreePathsFollowTheirMainFolder(path: String, oldPath: String, newPath: String, expected: String?) {
		#expect(GitWorktreeRepairer.relocated(path, from: oldPath, to: newPath) == expected)
	}

	@Test
	func movingTheMainFolderReconnectsItsWorktrees() async throws {
		let root = try makeFolder()
		defer { remove(root) }
		let main = root + "/main"
		let moved = root + "/moved"
		let external = root + "/external"
		try FileManager.default.createDirectory(atPath: main, withIntermediateDirectories: false)
		try await git(["init", "--initial-branch=main"], at: main)
		try await git(["-c", "user.email=t@example.com", "-c", "user.name=T", "commit", "--allow-empty", "-m", "base"], at: main)
		try await git(["worktree", "add", "-b", "nested", "nested/wt"], at: main)
		try await git(["worktree", "add", "-b", "external", external], at: main)

		try FileManager.default.moveItem(atPath: main, toPath: moved)
		await GitWorktreeRepairer.repairAfterMainMoved(from: main, to: moved)

		let paths = await GitWorktreeScanner.listWorktrees(forRepo: moved).map { GitWatchTarget.canonicalPath($0.path) }
		#expect(paths.contains(GitWatchTarget.canonicalPath(moved + "/nested/wt")))
		try await git(["status"], at: external)
		try await git(["status"], at: moved + "/nested/wt")
	}

	// MARK: - Helpers

	private func makeFolder() throws -> String {
		let folder = NSTemporaryDirectory() + "RepositoryLocationTests-" + UUID().uuidString
		try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
		return folder
	}

	private func remove(_ path: String) {
		try? FileManager.default.removeItem(atPath: path)
	}

	private func git(_ arguments: [String], at path: String) async throws {
		let result = await ProcessRunner.runGit(arguments: arguments, at: path)
		guard result.success else {
			throw GitError.logFailed("git \(arguments.joined(separator: " ")): \(result.errorString)")
		}
	}
}
