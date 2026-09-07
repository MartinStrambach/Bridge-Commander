import Testing

@testable import GitCore

@Suite("GitStagingHelper hunk parsing")
struct GitStagingHelperHunkParsingTests {

	// MARK: - Trailing Newline

	@Test("the trailing newline of git's output does not become an extra context line")
	func trailingNewlineIsNotALine() {
		let diff = """
		diff --git a/base.txt b/base.txt
		index abcdef1..1234567 100644
		--- a/base.txt
		+++ b/base.txt
		@@ -3,3 +3,4 @@
		 3
		 4
		 5
		+6

		"""

		let hunks = GitDiffHunkParser.parse(diff)

		#expect(hunks.count == 1)
		#expect(hunks[0].lines.map(\.rawLine) == [" 3", " 4", " 5", "+6"])
	}

	@Test("an added file parses as exactly as many lines as its hunk header declares")
	func addedFileLineCountMatchesHeader() {
		let addedLines = (1 ... 119).map { "+\($0)" }
		let diff = ([
			"diff --git a/new.txt b/new.txt",
			"new file mode 100644",
			"index 0000000..abcdef1",
			"--- /dev/null",
			"+++ b/new.txt",
			"@@ -0,0 +1,119 @@",
		] + addedLines).joined(separator: "\n") + "\n"

		let hunks = GitDiffHunkParser.parse(diff)

		#expect(hunks.count == 1)
		#expect(hunks[0].lines.count == 119)
		#expect(hunks[0].lines.last?.rawLine == "+119")
		#expect(hunks[0].lines.last?.newLineNumber == 119)
	}

	// MARK: - Line Numbering

	@Test("no phantom line number is handed out past the end of the last hunk")
	func lastHunkStopsAtItsLastRealLine() {
		// A change to line 10 of a 30-line file: the hunk covers lines 7...13, so nothing may be
		// numbered 14 — that line exists in the file but is not part of the diff.
		let diff = """
		diff --git a/mid.txt b/mid.txt
		index abcdef1..1234567 100644
		--- a/mid.txt
		+++ b/mid.txt
		@@ -7,7 +7,7 @@
		 7
		 8
		 9
		-10
		+10X
		 11
		 12
		 13

		"""

		let hunks = GitDiffHunkParser.parse(diff)

		#expect(hunks.count == 1)
		#expect(hunks[0].lines.count == 8)
		#expect(hunks[0].lines.last?.rawLine == " 13")
		#expect(hunks[0].lines.compactMap(\.newLineNumber).max() == 13)
	}

	// MARK: - Blank Lines In Content

	@Test("blank lines inside the diff are kept as context and additions")
	func blankContentLinesSurvive() {
		// git emits a blank context line as " " and a blank added line as "+", so neither is lost
		// when the trailing terminator is dropped.
		let diff = "diff --git a/gap.txt b/gap.txt\n"
			+ "--- a/gap.txt\n"
			+ "+++ b/gap.txt\n"
			+ "@@ -1,3 +1,4 @@\n"
			+ " a\n"
			+ " \n"
			+ "+\n"
			+ " b\n"

		let hunks = GitDiffHunkParser.parse(diff)

		#expect(hunks.count == 1)
		#expect(hunks[0].lines.map(\.rawLine) == [" a", " ", "+", " b"])
	}

	// MARK: - Output Without Hunk Headers

	// git omits the @@ header only when there are no line changes to describe, and in those cases it
	// omits the ---/+++ lines too. These are verbatim outputs for each such case.

	@Test("adding an empty file yields no hunks")
	func addedEmptyFileHasNoHunks() {
		let diff = """
		diff --git a/empty.txt b/empty.txt
		new file mode 100644
		index 0000000..e69de29

		"""

		#expect(GitDiffHunkParser.parse(diff).isEmpty)
	}

	@Test("deleting an empty file yields no hunks")
	func deletedEmptyFileHasNoHunks() {
		let diff = """
		diff --git a/empty.txt b/empty.txt
		deleted file mode 100644
		index e69de29..0000000

		"""

		#expect(GitDiffHunkParser.parse(diff).isEmpty)
	}

	@Test("a mode-only change yields no hunks")
	func modeOnlyChangeHasNoHunks() {
		let diff = """
		diff --git a/run.sh b/run.sh
		old mode 100644
		new mode 100755

		"""

		#expect(GitDiffHunkParser.parse(diff).isEmpty)
	}

	@Test("file header lines are never mistaken for content")
	func fileHeadersAreNotContent() {
		// "--- a/x" and "+++ b/x" start with "-" and "+", so a parser that scans for content before
		// finding the @@ header would read them as a deleted and an added line.
		let diff = """
		diff --git a/one.txt b/one.txt
		index abcdef1..1234567 100644
		--- a/one.txt
		+++ b/one.txt
		@@ -1 +1 @@
		-a
		+b

		"""

		let hunks = GitDiffHunkParser.parse(diff)

		#expect(hunks.count == 1)
		#expect(hunks[0].lines.map(\.rawLine) == ["-a", "+b"])
	}

	// MARK: - Multiple Hunks

	@Test("only the last hunk was affected, and it lines up with the earlier ones")
	func multipleHunksEachEndOnTheirOwnLastLine() {
		let diff = """
		diff --git a/multi.txt b/multi.txt
		--- a/multi.txt
		+++ b/multi.txt
		@@ -1,3 +1,3 @@
		-a
		+aX
		 b
		 c
		@@ -18,3 +18,3 @@ p
		 r
		-t
		+tX

		"""

		let hunks = GitDiffHunkParser.parse(diff)

		#expect(hunks.count == 2)
		#expect(hunks[0].lines.map(\.rawLine) == ["-a", "+aX", " b", " c"])
		#expect(hunks[1].lines.map(\.rawLine) == [" r", "-t", "+tX"])
	}

}
