import Foundation
import ProcessExecution
import Testing

@testable import GitCore

// The staging panel reads with `git diff`, which by default writes refreshed stat data back to the
// index — taking `index.lock` while a stage may be starting. These tests check that reading a file
// whose timestamps changed (but not its content) leaves the index file untouched.
@Suite("GitStagingHelper reads")
struct GitStagingHelperReadTests {

	private struct Repository {
		let path: String

		init() async throws {
			path = NSTemporaryDirectory() + "GitStagingHelperReadTests-" + UUID().uuidString
			try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
			try await git("init", "--initial-branch=main")
			try await git("config", "user.email", "test@example.com")
			try await git("config", "user.name", "Test")
			try await git("config", "commit.gpgsign", "false")
			try "same\n".write(toFile: path + "/touched.txt", atomically: true, encoding: .utf8)
			try "old\n".write(toFile: path + "/edited.txt", atomically: true, encoding: .utf8)
			try await git("add", ".")
			try await git("commit", "-m", "base")
		}

		func git(_ arguments: String...) async throws {
			let result = await ProcessRunner.runGit(arguments: arguments, at: path)
			guard result.success else {
				throw GitError.stagingFailed("git \(arguments.joined(separator: " ")): \(result.errorString)")
			}
		}

		/// `touched.txt` keeps its content but gets a new timestamp, so the index's stat data for it
		/// is out of date; `edited.txt` really changes.
		func makeChanges() throws {
			try FileManager.default.setAttributes(
				[.modificationDate: Date().addingTimeInterval(-3600)],
				ofItemAtPath: path + "/touched.txt"
			)
			try "new\n".write(toFile: path + "/edited.txt", atomically: true, encoding: .utf8)
		}

		func index() -> Data? {
			FileManager.default.contents(atPath: path + "/.git/index")
		}

		func remove() {
			try? FileManager.default.removeItem(atPath: path)
		}
	}

	@Test
	func fetchingFileChangesLeavesTheIndexAlone() async throws {
		let repository = try await Repository()
		defer { repository.remove() }
		try repository.makeChanges()
		let before = repository.index()

		let changes = await GitStagingHelper.fetchFileChanges(at: repository.path)

		#expect(changes.unstaged.map(\.path) == ["edited.txt"])
		#expect(changes.unstaged.first?.addedLines == 1)
		#expect(repository.index() == before)
	}

	@Test
	func fetchingADiffLeavesTheIndexAlone() async throws {
		let repository = try await Repository()
		defer { repository.remove() }
		try repository.makeChanges()
		let before = repository.index()

		let touched = await GitStagingHelper.fetchFileDiff(
			at: repository.path,
			file: FileChange(path: "touched.txt", status: .modified),
			isStaged: false
		)
		let edited = await GitStagingHelper.fetchFileDiff(
			at: repository.path,
			file: FileChange(path: "edited.txt", status: .modified),
			isStaged: false
		)

		#expect(touched == nil, "a file whose content did not change has no diff")
		#expect(edited?.hunks.count == 1)
		#expect(repository.index() == before)
	}
}
