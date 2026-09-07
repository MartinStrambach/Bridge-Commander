import Foundation
import Testing

@testable import GitCore

/// Every diff in this suite is verbatim `git diff` output for the case it describes.
@Suite("GitStagingHelper missing trailing newline")
struct GitStagingHelperNoNewlineTests {

	// MARK: - Parsing

	@Test("a marker after the new side's last line is recorded on that line")
	func markerOnAdditionOnly() {
		let diff = """
		diff --git a/add.txt b/add.txt
		--- a/add.txt
		+++ b/add.txt
		@@ -1,2 +1,2 @@
		 k
		-l
		+l
		\\ No newline at end of file

		"""

		let hunks = GitDiffHunkParser.parse(diff)

		#expect(hunks.count == 1)
		// The marker is not a line of its own, so it must not show up in the hunk's lines.
		#expect(hunks[0].lines.map(\.rawLine) == [" k", "-l", "+l"])
		#expect(hunks[0].lines.map(\.hasNoNewlineAtEndOfFile) == [false, false, true])
	}

	@Test("both markers are kept when neither side is newline-terminated")
	func markerOnBothSides() {
		let diff = """
		diff --git a/two.txt b/two.txt
		--- a/two.txt
		+++ b/two.txt
		@@ -1,2 +1,2 @@
		 a
		-b
		\\ No newline at end of file
		+bb
		\\ No newline at end of file

		"""

		let hunks = GitDiffHunkParser.parse(diff)

		#expect(hunks.count == 1)
		#expect(hunks[0].lines.map(\.rawLine) == [" a", "-b", "+bb"])
		// A single hunk carries one marker for the old side's last line and one for the new side's.
		#expect(hunks[0].lines.map(\.hasNoNewlineAtEndOfFile) == [false, true, true])
	}

	@Test("a marker after a context line is recorded on that line")
	func markerOnContextLine() {
		let diff = """
		diff --git a/ctx.txt b/ctx.txt
		--- a/ctx.txt
		+++ b/ctx.txt
		@@ -1,3 +1,3 @@
		 x
		-y
		+yy
		 z
		\\ No newline at end of file

		"""

		let hunks = GitDiffHunkParser.parse(diff)

		#expect(hunks.count == 1)
		#expect(hunks[0].lines.map(\.rawLine) == [" x", "-y", "+yy", " z"])
		#expect(hunks[0].lines.last?.hasNoNewlineAtEndOfFile == true)
		// The marker must not consume a line number either.
		#expect(hunks[0].lines.compactMap(\.newLineNumber).max() == 3)
	}

	@Test("the flag survives inline change highlighting")
	func flagSurvivesInlineHighlighting() {
		// The highlighter rebuilds changed lines through withInlineChanges, which would drop the flag
		// if it were not carried over — and it is exactly the changed lines that tend to hold it.
		// The pair has to share enough tokens for the highlighter to match it up.
		let diff = """
		diff --git a/Config.swift b/Config.swift
		--- a/Config.swift
		+++ b/Config.swift
		@@ -1,2 +1,2 @@
		 enum Config {
		-    static let retries = 1
		\\ No newline at end of file
		+    static let retries = 2
		\\ No newline at end of file

		"""

		let hunks = GitDiffHunkParser.parse(diff)
		let rebuilt = hunks[0].lines.filter { !$0.inlineChanges.isEmpty }

		#expect(!rebuilt.isEmpty, "expected the highlighter to have annotated the changed pair")
		#expect(rebuilt.allSatisfy { $0.hasNoNewlineAtEndOfFile })
	}

	@Test("a content line whose own text starts with a backslash is not a marker")
	func backslashContentIsNotAMarker() {
		let diff = """
		diff --git a/tex.txt b/tex.txt
		--- a/tex.txt
		+++ b/tex.txt
		@@ -1,2 +1,2 @@
		 \\section{a}
		-\\newcommand{b}
		+\\newcommand{c}

		"""

		let hunks = GitDiffHunkParser.parse(diff)

		#expect(hunks.count == 1)
		#expect(hunks[0].lines.map(\.rawLine) == [" \\section{a}", "-\\newcommand{b}", "+\\newcommand{c}"])
		#expect(hunks[0].lines.allSatisfy { !$0.hasNoNewlineAtEndOfFile })
	}

	// MARK: - Patch Generation

	@Test("the marker is written back into the patch, on the line it belongs to")
	func patchRestoresBothMarkers() {
		let diff = """
		diff --git a/two.txt b/two.txt
		--- a/two.txt
		+++ b/two.txt
		@@ -1,2 +1,2 @@
		 a
		-b
		\\ No newline at end of file
		+bb
		\\ No newline at end of file

		"""

		let hunks = GitDiffHunkParser.parse(diff)
		let patch = GitStagingHelper.createPatchForHunk(
			at: "/tmp",
			file: FileChange(path: "two.txt", status: .modified),
			hunk: hunks[0]
		)

		#expect(patch == """
		diff --git a/two.txt b/two.txt
		--- a/two.txt
		+++ b/two.txt
		@@ -1,2 +1,2 @@
		 a
		-b
		\\ No newline at end of file
		+bb
		\\ No newline at end of file

		""")
	}

	@Test("a hunk with no unterminated line produces no marker")
	func patchWithoutMarkerIsUnchanged() {
		let diff = """
		diff --git a/plain.txt b/plain.txt
		--- a/plain.txt
		+++ b/plain.txt
		@@ -1,2 +1,2 @@
		 a
		-b
		+bb

		"""

		let hunks = GitDiffHunkParser.parse(diff)
		let patch = GitStagingHelper.createPatchForHunk(
			at: "/tmp",
			file: FileChange(path: "plain.txt", status: .modified),
			hunk: hunks[0]
		)

		#expect(!patch.contains("No newline"))
	}

	// MARK: - Untracked Files

	@Test("an untracked file with no trailing newline is marked in its synthetic diff")
	func untrackedFileWithoutTrailingNewline() async throws {
		let directory = try makeTemporaryDirectory()
		defer { try? FileManager.default.removeItem(atPath: directory) }
		try "x\ny\nz".write(
			toFile: (directory as NSString).appendingPathComponent("nonl.txt"),
			atomically: true,
			encoding: .utf8
		)
		let file = FileChange(path: "nonl.txt", status: .untracked)

		let diff = await GitStagingHelper.fetchFileDiff(at: directory, file: file, isStaged: false)

		let hunk = try #require(diff?.hunks.first)
		#expect(hunk.lines.map(\.rawLine) == ["+x", "+y", "+z"])
		#expect(hunk.lines.map(\.hasNoNewlineAtEndOfFile) == [false, false, true])

		// Without the marker the patch would stage a trailing newline the file does not have, so the
		// file would come back as modified the moment it was staged.
		let patch = GitStagingHelper.createPatchForHunk(at: directory, file: file, hunk: hunk)
		#expect(patch.hasSuffix("+z\n\\ No newline at end of file\n"))
	}

	@Test("an untracked file that ends in a newline gets no marker")
	func untrackedFileWithTrailingNewline() async throws {
		let directory = try makeTemporaryDirectory()
		defer { try? FileManager.default.removeItem(atPath: directory) }
		try "x\ny\nz\n".write(
			toFile: (directory as NSString).appendingPathComponent("nl.txt"),
			atomically: true,
			encoding: .utf8
		)
		let file = FileChange(path: "nl.txt", status: .untracked)

		let diff = await GitStagingHelper.fetchFileDiff(at: directory, file: file, isStaged: false)

		let lines = try #require(diff?.hunks.first?.lines)
		#expect(lines.map(\.rawLine) == ["+x", "+y", "+z"])
		#expect(lines.allSatisfy { !$0.hasNoNewlineAtEndOfFile })
	}

	// MARK: - Helpers

	private func makeTemporaryDirectory() throws -> String {
		let path = FileManager.default.temporaryDirectory
			.appendingPathComponent("GitStagingHelperNoNewlineTests-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
		return path.path
	}

}
