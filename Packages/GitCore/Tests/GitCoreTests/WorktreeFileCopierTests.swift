import Foundation
import Testing
@testable import GitCore

@Suite("WorktreeFileCopier")
final class WorktreeFileCopierTests {
	private let fm = FileManager.default
	private let root: URL
	private let sourceRepo: URL
	private let worktree: URL

	init() throws {
		root = fm.temporaryDirectory
			.appendingPathComponent("WorktreeFileCopierTests-\(UUID().uuidString)")
		sourceRepo = root.appendingPathComponent("repo")
		worktree = root.appendingPathComponent("worktree")
		try fm.createDirectory(at: sourceRepo, withIntermediateDirectories: true)
		try fm.createDirectory(at: worktree, withIntermediateDirectories: true)
	}

	deinit {
		try? FileManager.default.removeItem(at: root)
	}

	private func writeSourceFile(_ relativePath: String, contents: String = "content") throws {
		let url = sourceRepo.appendingPathComponent(relativePath)
		try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
		try contents.write(to: url, atomically: true, encoding: .utf8)
	}

	private func worktreeContents(of relativePath: String) throws -> String {
		try String(contentsOf: worktree.appendingPathComponent(relativePath), encoding: .utf8)
	}

	// MARK: - Successful copies

	@Test("copies a top-level file with its contents")
	func copiesTopLevelFile() throws {
		try writeSourceFile(".env", contents: "SECRET=1")

		let result = WorktreeFileCopier.copy(paths: [".env"], from: sourceRepo, to: worktree)

		#expect(result.copied == [".env"])
		#expect(result.missing.isEmpty)
		#expect(result.failed.isEmpty)
		#expect(!result.hasWarnings)
		#expect(try worktreeContents(of: ".env") == "SECRET=1")
	}

	@Test("copies a nested file, creating intermediate directories")
	func copiesNestedFileCreatingParents() throws {
		try writeSourceFile("Tuist/.env", contents: "TOKEN=x")

		let result = WorktreeFileCopier.copy(paths: ["Tuist/.env"], from: sourceRepo, to: worktree)

		#expect(result.copied == ["Tuist/.env"])
		#expect(try worktreeContents(of: "Tuist/.env") == "TOKEN=x")
	}

	@Test("copies a directory recursively")
	func copiesDirectoryRecursively() throws {
		try writeSourceFile("config/local/a.txt", contents: "a")
		try writeSourceFile("config/local/sub/b.txt", contents: "b")

		let result = WorktreeFileCopier.copy(paths: ["config/local"], from: sourceRepo, to: worktree)

		#expect(result.copied == ["config/local"])
		#expect(try worktreeContents(of: "config/local/a.txt") == "a")
		#expect(try worktreeContents(of: "config/local/sub/b.txt") == "b")
	}

	@Test("accepts a directory path with a trailing slash")
	func acceptsTrailingSlashDirectory() throws {
		try writeSourceFile("config/local/a.txt", contents: "a")

		let result = WorktreeFileCopier.copy(paths: ["config/local/"], from: sourceRepo, to: worktree)

		#expect(result.copied.count == 1)
		#expect(result.failed.isEmpty)
		#expect(result.missing.isEmpty)
		#expect(try worktreeContents(of: "config/local/a.txt") == "a")
	}

	@Test("trims surrounding whitespace from paths")
	func trimsWhitespace() throws {
		try writeSourceFile(".env", contents: "x")

		let result = WorktreeFileCopier.copy(paths: ["  .env  "], from: sourceRepo, to: worktree)

		#expect(result.copied == [".env"])
		#expect(try worktreeContents(of: ".env") == "x")
	}

	// MARK: - Skipped and missing paths

	@Test("skips empty and whitespace-only entries without reporting them")
	func skipsEmptyEntries() throws {
		let result = WorktreeFileCopier.copy(paths: ["", "   ", "\t"], from: sourceRepo, to: worktree)

		#expect(result.copied.isEmpty)
		#expect(result.missing.isEmpty)
		#expect(result.failed.isEmpty)
		#expect(!result.hasWarnings)
	}

	@Test("reports paths absent from the source repository as missing")
	func reportsMissingPaths() throws {
		let result = WorktreeFileCopier.copy(paths: ["no-such-file"], from: sourceRepo, to: worktree)

		#expect(result.copied.isEmpty)
		#expect(result.missing == ["no-such-file"])
		#expect(result.failed.isEmpty)
		#expect(result.hasWarnings)
	}

	// MARK: - Invalid paths

	@Test("rejects absolute paths")
	func rejectsAbsolutePaths() throws {
		let result = WorktreeFileCopier.copy(paths: ["/etc/hosts"], from: sourceRepo, to: worktree)

		#expect(result.copied.isEmpty)
		#expect(result.failed.count == 1)
		#expect(result.failed[0].path == "/etc/hosts")
		#expect(result.failed[0].reason.contains("invalid path"))
		#expect(result.hasWarnings)
	}

	@Test("rejects paths that traverse out of the repository")
	func rejectsParentTraversal() throws {
		let result = WorktreeFileCopier.copy(
			paths: ["..", "../outside.txt", "a/../b"],
			from: sourceRepo,
			to: worktree
		)

		#expect(result.copied.isEmpty)
		#expect(result.failed.count == 3)
		#expect(result.failed.allSatisfy { $0.reason.contains("invalid path") })
	}

	@Test("allows filenames that merely contain dots")
	func allowsDottedFilenames() throws {
		try writeSourceFile("..config", contents: "ok")

		let result = WorktreeFileCopier.copy(paths: ["..config"], from: sourceRepo, to: worktree)

		#expect(result.copied == ["..config"])
		#expect(try worktreeContents(of: "..config") == "ok")
	}

	// MARK: - Destination conflicts

	@Test("does not overwrite an existing destination and reports a failure")
	func doesNotOverwriteExistingDestination() throws {
		try writeSourceFile(".env", contents: "new")
		try "original".write(
			to: worktree.appendingPathComponent(".env"),
			atomically: true,
			encoding: .utf8
		)

		let result = WorktreeFileCopier.copy(paths: [".env"], from: sourceRepo, to: worktree)

		#expect(result.copied.isEmpty)
		#expect(result.failed == [.init(path: ".env", reason: "destination already exists")])
		#expect(try worktreeContents(of: ".env") == "original")
	}

	@Test("a duplicate entry fails on the second copy but keeps the first")
	func duplicateEntryFailsSecondCopy() throws {
		try writeSourceFile(".env", contents: "x")

		let result = WorktreeFileCopier.copy(paths: [".env", ".env"], from: sourceRepo, to: worktree)

		#expect(result.copied == [".env"])
		#expect(result.failed == [.init(path: ".env", reason: "destination already exists")])
		#expect(try worktreeContents(of: ".env") == "x")
	}

	// MARK: - Mixed batches

	@Test("one bad entry does not stop the remaining copies")
	func badEntryDoesNotStopBatch() throws {
		try writeSourceFile("a.txt", contents: "a")
		try writeSourceFile("b.txt", contents: "b")

		let result = WorktreeFileCopier.copy(
			paths: ["a.txt", "/absolute", "gone.txt", "b.txt"],
			from: sourceRepo,
			to: worktree
		)

		#expect(result.copied == ["a.txt", "b.txt"])
		#expect(result.missing == ["gone.txt"])
		#expect(result.failed.map(\.path) == ["/absolute"])
		#expect(result.hasWarnings)
		#expect(try worktreeContents(of: "a.txt") == "a")
		#expect(try worktreeContents(of: "b.txt") == "b")
	}
}
