import Foundation
import Testing

@testable import GitCore

@Suite("GitStagingHelper patch generation")
struct GitStagingHelperPatchTests {

	// MARK: - Helpers

	private func makeTemporaryDirectory() throws -> String {
		let path = FileManager.default.temporaryDirectory
			.appendingPathComponent("GitStagingHelperPatchTests-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
		return path.path
	}

	private func write(_ contents: String, to fileName: String, in directory: String, executable: Bool = false) throws {
		let fullPath = (directory as NSString).appendingPathComponent(fileName)
		try contents.write(toFile: fullPath, atomically: true, encoding: .utf8)
		if executable {
			try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fullPath)
		}
	}

	private func hunk() -> DiffHunk {
		DiffHunk(
			header: "@@ -0,0 +1,2 @@",
			oldStart: 0,
			oldCount: 0,
			newStart: 1,
			newCount: 2,
			lines: [
				DiffLine(rawLine: "+a", id: "0", oldLineNumber: nil, newLineNumber: 1),
				DiffLine(rawLine: "+b", id: "1", oldLineNumber: nil, newLineNumber: 2),
			]
		)
	}

	// MARK: - New Files

	@Test("a patch that creates a file declares the new file mode")
	func untrackedFileDeclaresNewFileMode() throws {
		let directory = try makeTemporaryDirectory()
		defer { try? FileManager.default.removeItem(atPath: directory) }
		try write("a\nb\n", to: "new.txt", in: directory)

		let patch = GitStagingHelper.createPatchForHunk(
			at: directory,
			file: FileChange(path: "new.txt", status: .untracked),
			hunk: hunk()
		)

		// The mode line has to sit between the "diff --git" line and the "---" line, where git puts it.
		#expect(patch.hasPrefix("""
		diff --git a/new.txt b/new.txt
		new file mode 100644
		--- /dev/null
		+++ b/new.txt
		"""))
	}

	@Test("a staged addition declares the new file mode too")
	func addedFileDeclaresNewFileMode() throws {
		let directory = try makeTemporaryDirectory()
		defer { try? FileManager.default.removeItem(atPath: directory) }
		try write("a\nb\n", to: "new.txt", in: directory)

		let patch = GitStagingHelper.createPatchForHunk(
			at: directory,
			file: FileChange(path: "new.txt", status: .added),
			hunk: hunk()
		)

		#expect(patch.contains("new file mode 100644\n"))
	}

	@Test("an executable new file keeps its executable bit")
	func executableFileUsesExecutableMode() throws {
		let directory = try makeTemporaryDirectory()
		defer { try? FileManager.default.removeItem(atPath: directory) }
		try write("a\nb\n", to: "script.sh", in: directory, executable: true)

		let patch = GitStagingHelper.createPatchForHunk(
			at: directory,
			file: FileChange(path: "script.sh", status: .untracked),
			hunk: hunk()
		)

		// git takes the mode literally, so 100644 here would stage the file without its +x bit.
		#expect(patch.contains("new file mode 100755\n"))
	}

	@Test("a new file in a subdirectory is resolved relative to the repository")
	func nestedFileModeIsResolvedFromRepositoryRoot() throws {
		let directory = try makeTemporaryDirectory()
		defer { try? FileManager.default.removeItem(atPath: directory) }
		let nested = (directory as NSString).appendingPathComponent("scripts")
		try FileManager.default.createDirectory(atPath: nested, withIntermediateDirectories: true)
		try write("a\nb\n", to: "scripts/run.sh", in: directory, executable: true)

		let patch = GitStagingHelper.createPatchForHunk(
			at: directory,
			file: FileChange(path: "scripts/run.sh", status: .untracked),
			hunk: hunk()
		)

		#expect(patch.contains("new file mode 100755\n"))
	}

	// MARK: - Other Statuses

	@Test("a deletion needs no mode line and keeps its /dev/null target")
	func deletedFileHasNoModeLine() throws {
		let directory = try makeTemporaryDirectory()
		defer { try? FileManager.default.removeItem(atPath: directory) }

		let patch = GitStagingHelper.createPatchForHunk(
			at: directory,
			file: FileChange(path: "gone.txt", status: .deleted),
			hunk: DiffHunk(
				header: "@@ -1,1 +0,0 @@",
				oldStart: 1,
				oldCount: 1,
				newStart: 0,
				newCount: 0,
				lines: [DiffLine(rawLine: "-a", id: "0", oldLineNumber: 1, newLineNumber: nil)]
			)
		)

		#expect(!patch.contains("file mode"))
		#expect(patch.contains("--- a/gone.txt\n+++ /dev/null\n"))
	}

	@Test("a modification is unchanged by the new file mode handling")
	func modifiedFileHasNoModeLine() throws {
		let directory = try makeTemporaryDirectory()
		defer { try? FileManager.default.removeItem(atPath: directory) }
		try write("a\nb\n", to: "edit.txt", in: directory, executable: true)

		let patch = GitStagingHelper.createPatchForHunk(
			at: directory,
			file: FileChange(path: "edit.txt", status: .modified),
			hunk: hunk()
		)

		// Even for an executable file, a modification must not gain a mode line.
		#expect(!patch.contains("file mode"))
		#expect(patch.contains("--- a/edit.txt\n+++ b/edit.txt\n"))
	}

}
