import Testing

@testable import GitCore

struct GitBinaryDiffDetectorTests {

	@Test
	func recognisesModifiedBinaryMarker() {
		let output = """
		diff --git a/Assets/logo.png b/Assets/logo.png
		index 1634155..4e4e315 100644
		Binary files a/Assets/logo.png and b/Assets/logo.png differ

		"""
		#expect(GitBinaryDiffDetector.isBinaryDiff(output))
	}

	@Test
	func recognisesDeletedBinaryMarker() {
		let output = """
		diff --git a/Assets/logo.png b/Assets/logo.png
		deleted file mode 100644
		index 1634155..0000000
		Binary files a/Assets/logo.png and /dev/null differ
		"""
		#expect(GitBinaryDiffDetector.isBinaryDiff(output))
	}

	@Test
	func ignoresTheMarkerTextInsideFileContent() {
		// A source file that mentions git's own wording is still a text diff: content lines are
		// prefixed with +, - or a space, so the marker never starts at column 0.
		let output = """
		diff --git a/Sources/GitStagingHelper.swift b/Sources/GitStagingHelper.swift
		index 9bbf8db..d879316 100644
		--- a/Sources/GitStagingHelper.swift
		+++ b/Sources/GitStagingHelper.swift
		@@ -118,7 +118,7 @@
		 		// Check if binary file
		 		if diffOutput.contains("Binary files") {
		-			return FileDiff(fileChange: file, hunks: [], isBinary: true)
		+			return await binaryFileDiff(at: repositoryPath, file: file, isStaged: isStaged)
		 		}
		+// Binary files a/x and b/y differ
		-Binary files a/x and b/y differ
		"""
		#expect(!GitBinaryDiffDetector.isBinaryDiff(output))
	}

	@Test
	func plainTextDiffIsNotBinary() {
		let output = """
		diff --git a/README.md b/README.md
		--- a/README.md
		+++ b/README.md
		@@ -1 +1 @@
		-old
		+new
		"""
		#expect(!GitBinaryDiffDetector.isBinaryDiff(output))
	}

	@Test
	func emptyOutputIsNotBinary() {
		#expect(!GitBinaryDiffDetector.isBinaryDiff(""))
	}
}
