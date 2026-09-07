import Foundation
import ProcessExecution

public nonisolated enum GitStagingHelper {

	private static let hunkHeaderRegex = try? NSRegularExpression(
		pattern: #"@@ -(\d+),?(\d*) \+(\d+),?(\d*) @@"#
	)

	// MARK: - Fetch File Changes

	public static func fetchFileChanges(at path: String) async -> GitFileChanges {
		async let statusTask = GitStatusDetector.getStatus(at: path)
		async let stagedStatsTask = fetchLineStats(at: path, staged: true)
		async let unstagedStatsTask = fetchLineStats(at: path, staged: false)

		let status = await statusTask
		let stagedStats = await stagedStatsTask
		let unstagedStats = await unstagedStatsTask

		return GitFileChanges(
			staged: status.staged
				.sorted { $0.path < $1.path }
				.map { $0.withLineStats(stagedStats[$0.path]) },
			unstaged: status.unstaged
				.sorted { $0.path < $1.path }
				.map { $0.withLineStats($0.status == .untracked ? untrackedLineStats(at: path, file: $0) : unstagedStats[$0.path]) },
			unpushedCount: status.unpushedCount
		)
	}

	// MARK: - Line Stats

	private static func fetchLineStats(at repositoryPath: String, staged: Bool) async -> [String: GitLineStats] {
		var arguments = ["diff", "--numstat", "-z", "-M"]
		if staged {
			arguments.append("--cached")
		}

		let result = await ProcessRunner.runGit(arguments: arguments, at: repositoryPath)
		guard result.success else {
			return [:]
		}

		return GitNumstatParser.parse(result.outputString)
	}

	/// Untracked files never appear in `git diff`, so count their lines directly.
	/// Returns nil for binary or unusually large files.
	private static func untrackedLineStats(at repositoryPath: String, file: FileChange) -> GitLineStats? {
		let maxCountableFileSize = 4 * 1024 * 1024
		let fullPath = (repositoryPath as NSString).appendingPathComponent(file.path)

		guard
			let attributes = try? FileManager.default.attributesOfItem(atPath: fullPath),
			let size = attributes[.size] as? Int,
			size <= maxCountableFileSize
		else {
			return nil
		}
		guard size > 0 else {
			return GitLineStats(added: 0, removed: 0)
		}
		guard let data = FileManager.default.contents(atPath: fullPath), !data.contains(0) else {
			return nil // unreadable or binary
		}

		let newline = UInt8(ascii: "\n")
		var lines = data.count(where: { $0 == newline })
		if data.last != newline {
			lines += 1
		}
		return GitLineStats(added: lines, removed: 0)
	}

	// MARK: - Fetch Diff

	public static func fetchFileDiff(
		at repositoryPath: String,
		file: FileChange,
		isStaged: Bool
	) async -> FileDiff? {
		// For untracked files, create synthetic diff from file content
		if file.status == .untracked {
			return await createUntrackedFileDiff(at: repositoryPath, file: file, isStaged: isStaged)
		}

		// For added files in staged area, use synthetic diff
		if file.status == .added, isStaged {
			return await createUntrackedFileDiff(at: repositoryPath, file: file, isStaged: isStaged)
		}

		// For tracked files, use git diff
		let arguments: [String] =
			if isStaged {
				if file.status == .renamed, let oldPath = file.oldPath {
					["diff", "--cached", "--", oldPath, file.path]
				} else {
					["diff", "--cached", "--", file.path]
				}
			}
			else {
				["diff", "--", file.path]
			}

		let result = await ProcessRunner.runGit(arguments: arguments, at: repositoryPath)
		guard result.success else {
			return nil
		}

		let diffOutput = result.outputString

		// Check if empty output (trim only for the check)
		if diffOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
			return nil
		}

		if GitBinaryDiffDetector.isBinaryDiff(diffOutput) {
			return await binaryFileDiff(at: repositoryPath, file: file, isStaged: isStaged)
		}

		let hunks = parseDiffIntoHunks(diffOutput)
		return FileDiff(fileChange: file, hunks: hunks, isBinary: false)
	}

	// MARK: - Stage Files

	public static func stageFiles(at repositoryPath: String, filePaths: [String]) async throws {
		guard !filePaths.isEmpty else {
			return
		}

		// Build arguments with all file paths
		// Use -f to handle tracked files that match .gitignore patterns (git add exits 1 with a
		// warning for these even though it stages them successfully).
		let arguments = ["add", "-f", "--"] + filePaths
		let result = await ProcessRunner.runGit(arguments: arguments, at: repositoryPath)
		guard result.success else {
			throw GitError.stagingFailed("Failed to stage files")
		}
	}

	// MARK: - Unstage Files

	public static func unstageFiles(at repositoryPath: String, filePaths: [String]) async throws {
		guard !filePaths.isEmpty else {
			return
		}

		// Build arguments with all file paths
		let arguments = ["reset", "HEAD", "--"] + filePaths
		let result = await ProcessRunner.runGit(arguments: arguments, at: repositoryPath)
		guard result.success else {
			throw GitError.stagingFailed("Failed to unstage files")
		}
	}

	// MARK: - Stage Hunk

	public static func stageHunk(
		at repositoryPath: String,
		file: FileChange,
		hunk: DiffHunk
	) async throws {
		try await applyPatch(
			at: repositoryPath,
			file: file,
			hunk: hunk,
			arguments: ["apply", "--cached", "--whitespace=nowarn"],
			errorMessage: "Failed to stage hunk"
		)
	}

	// MARK: - Unstage Hunk

	public static func unstageHunk(
		at repositoryPath: String,
		file: FileChange,
		hunk: DiffHunk
	) async throws {
		try await applyPatch(
			at: repositoryPath,
			file: file,
			hunk: hunk,
			arguments: ["apply", "--cached", "--reverse", "--whitespace=nowarn"],
			errorMessage: "Failed to unstage hunk"
		)
	}

	// MARK: - Discard Hunk

	public static func discardHunk(
		at repositoryPath: String,
		file: FileChange,
		hunk: DiffHunk
	) async throws {
		try await applyPatch(
			at: repositoryPath,
			file: file,
			hunk: hunk,
			arguments: ["apply", "-R", "--whitespace=nowarn"],
			errorMessage: "Failed to discard hunk"
		)
	}

	// MARK: - Discard File Changes

	public static func discardFileChanges(at repositoryPath: String, filePaths: [String]) async throws {
		guard !filePaths.isEmpty else {
			return
		}

		// Restore from index (not HEAD) so staged changes are preserved
		let arguments = ["checkout", "--"] + filePaths
		let result = await ProcessRunner.runGit(arguments: arguments, at: repositoryPath)
		guard result.success else {
			throw GitError.stagingFailed("Failed to discard changes")
		}
	}

	// MARK: - Delete Conflicted Files

	public static func deleteConflictedFiles(at repositoryPath: String, filePaths: [String]) async throws {
		guard !filePaths.isEmpty else {
			return
		}

		let arguments = ["rm", "--force", "--"] + filePaths
		let result = await ProcessRunner.runGit(arguments: arguments, at: repositoryPath)
		guard result.success else {
			throw GitError.stagingFailed("Failed to delete conflicted files")
		}
	}

	// MARK: - Commit

	public static func commit(at path: String, message: String) async throws {
		let result = await ProcessRunner.runGit(arguments: ["commit", "-m", message], at: path)
		guard result.success else {
			let errMsg = result.errorString.isEmpty ? result.outputString : result.errorString
			throw GitError.commitFailed(errMsg)
		}
	}

	// MARK: - Delete Untracked Files

	public static func deleteUntrackedFiles(at repositoryPath: String, filePaths: [String]) async throws {
		guard !filePaths.isEmpty else {
			return
		}

		// Delete files using FileManager
		for filePath in filePaths {
			let fullPath = (repositoryPath as NSString).appendingPathComponent(filePath)
			do {
				try FileManager.default.removeItem(atPath: fullPath)
			}
			catch {
				throw GitError.fileOperationFailed("Failed to delete file: \(error.localizedDescription)")
			}
		}
	}

	// MARK: - Untracked File Diff

	private static func createUntrackedFileDiff(
		at repositoryPath: String,
		file: FileChange,
		isStaged: Bool
	) async -> FileDiff? {
		let fullPath = (repositoryPath as NSString).appendingPathComponent(file.path)
		var isDirectory: ObjCBool = false

		guard
			FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDirectory),
			!isDirectory.boolValue
		else {
			return nil
		}
		guard let content = try? String(contentsOf: URL(fileURLWithPath: fullPath), encoding: .utf8) else {
			return await binaryFileDiff(at: repositoryPath, file: file, isStaged: isStaged)
		}

		var lines = content.split(separator: "\n", omittingEmptySubsequences: false)
		if lines.last?.isEmpty == true {
			lines = lines.dropLast()
		}

		let diffLines = lines.map { "+" + $0 }
		let lineCount = diffLines.count
		let hunkHeader = "@@ -0,0 +1,\(lineCount) @@"

		// git records an unterminated final line with a marker, and so must this synthetic diff:
		// without it the generated patch stages the file with a newline the working tree copy does
		// not have, leaving it modified the moment it is staged.
		let linesWithoutTrailingNewline: Set<Int> =
			if lineCount > 0, !content.hasSuffix("\n") {
				[lineCount - 1]
			}
			else {
				[]
			}

		let hunk = DiffHunk(
			header: hunkHeader,
			oldStart: 0,
			oldCount: 0,
			newStart: 1,
			newCount: lineCount,
			lines: makeNumberedDiffLines(
				diffLines,
				hunkHeader: hunkHeader,
				oldStart: 0,
				newStart: 1,
				linesWithoutTrailingNewline: linesWithoutTrailingNewline
			)
		)

		return FileDiff(fileChange: file, hunks: [hunk], isBinary: false)
	}

	// MARK: - Binary File Diff

	/// A binary change has no hunks; when the file is an image, both versions are loaded so the
	/// viewer can show them instead of a placeholder.
	private static func binaryFileDiff(
		at repositoryPath: String,
		file: FileChange,
		isStaged: Bool
	) async -> FileDiff {
		let imageDiff = await GitImageDiffLoader.load(at: repositoryPath, file: file, isStaged: isStaged)
		return FileDiff(fileChange: file, hunks: [], isBinary: true, imageDiff: imageDiff)
	}

	// MARK: - Private Helpers

	private static func applyPatch(
		at repositoryPath: String,
		file: FileChange,
		hunk: DiffHunk,
		arguments: [String],
		errorMessage: String
	) async throws {
		let patch = createPatchForHunk(at: repositoryPath, file: file, hunk: hunk)
		let tempDir = FileManager.default.temporaryDirectory
		let patchFile = tempDir.appendingPathComponent("patch_\(UUID().uuidString).patch")

		try patch.write(to: patchFile, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: patchFile) }

		let fullArguments = arguments + [patchFile.path()]
		let result = await ProcessRunner.runGit(arguments: fullArguments, at: repositoryPath)

		guard result.success else {
			let detail = result.errorString.isEmpty ? "Unknown error" : result.errorString
			throw GitError.stagingFailed("\(errorMessage): \(detail)")
		}
	}

	/// Parses `git diff` output into hunks. Output that describes no line changes — an empty file
	/// being added or deleted, a mode-only change — carries no `@@` header and yields no hunks.
	static func parseDiffIntoHunks(_ diffOutput: String) -> [DiffHunk] {
		var hunks: [DiffHunk] = []
		var lines = diffOutput.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

		// `git diff` terminates its output with a newline, so the final split component is the empty
		// remainder after that newline rather than a line of the diff. Every content line git emits
		// carries a " ", "+" or "-" prefix, so an empty component can only be that terminator —
		// keeping it would append a phantom blank context line to the last hunk (a 119-line added
		// file would parse as 120 lines, contradicting its own "@@ -0,0 +1,119 @@" header).
		if lines.last?.isEmpty == true {
			lines.removeLast()
		}

		var currentHunkLines: [String] = []
		var linesWithoutTrailingNewline: Set<Int> = []
		var currentHunkHeader: String?
		var hunkHeaderParts: (oldStart: Int, oldCount: Int, newStart: Int, newCount: Int)?

		func saveCurrentHunk() {
			guard let header = currentHunkHeader, let parts = hunkHeaderParts else {
				return
			}

			let diffLines = makeNumberedDiffLines(
				currentHunkLines,
				hunkHeader: header,
				oldStart: parts.oldStart,
				newStart: parts.newStart,
				linesWithoutTrailingNewline: linesWithoutTrailingNewline
			)
			hunks.append(
				DiffHunk(
					header: header,
					oldStart: parts.oldStart,
					oldCount: parts.oldCount,
					newStart: parts.newStart,
					newCount: parts.newCount,
					lines: InlineDiffHighlighter.apply(to: diffLines)
				)
			)
		}

		for line in lines {
			if line.hasPrefix("@@") {
				saveCurrentHunk()
				currentHunkHeader = line
				hunkHeaderParts = parseHunkHeader(line)
				currentHunkLines = []
				linesWithoutTrailingNewline = []
			}
			else if currentHunkHeader != nil {
				// Content lines are checked first: a line whose own text starts with a backslash
				// still arrives prefixed by "+", "-" or " ", so only a bare backslash is a marker.
				if line.hasPrefix("+") || line.hasPrefix("-") || line.hasPrefix(" ") {
					currentHunkLines.append(line)
				}
				else if line.hasPrefix("\\") {
					// A hunk can carry two markers — one for the old side's last line and one for the
					// new side's — so this records against the preceding line rather than the hunk.
					if let lastIndex = currentHunkLines.indices.last {
						linesWithoutTrailingNewline.insert(lastIndex)
					}
				}
				else if line.isEmpty {
					currentHunkLines.append(" ")
				}
			}
		}

		saveCurrentHunk()
		return hunks
	}

	private static func makeNumberedDiffLines(
		_ rawLines: [String],
		hunkHeader: String,
		oldStart: Int,
		newStart: Int,
		linesWithoutTrailingNewline: Set<Int> = []
	) -> [DiffLine] {
		var oldLine = oldStart
		var newLine = newStart
		var result: [DiffLine] = []
		result.reserveCapacity(rawLines.count)

		for (index, rawLine) in rawLines.enumerated() {
			let oldNum: Int?
			let newNum: Int?

			if rawLine.hasPrefix("+") {
				oldNum = nil
				newNum = newLine
				newLine += 1
			}
			else if rawLine.hasPrefix("-") {
				oldNum = oldLine
				newNum = nil
				oldLine += 1
			}
			else {
				oldNum = oldLine
				newNum = newLine
				oldLine += 1
				newLine += 1
			}

			result.append(DiffLine(
				rawLine: rawLine,
				id: "\(hunkHeader):\(index)",
				oldLineNumber: oldNum,
				newLineNumber: newNum,
				hasNoNewlineAtEndOfFile: linesWithoutTrailingNewline.contains(index)
			))
		}

		return result
	}

	private static func parseHunkHeader(_ header: String) -> (
		oldStart: Int, oldCount: Int, newStart: Int, newCount: Int
	) {
		guard
			let regex = hunkHeaderRegex,
			let match = regex.firstMatch(
				in: header,
				range: NSRange(header.startIndex..., in: header)
			)
		else {
			return (0, 0, 0, 0)
		}

		let oldStart = extractInt(from: header, match: match, group: 1)
		let oldCount = extractInt(from: header, match: match, group: 2)
		let newStart = extractInt(from: header, match: match, group: 3)
		let newCount = extractInt(from: header, match: match, group: 4)

		return (oldStart, oldCount, newStart, newCount)
	}

	private static func extractInt(from string: String, match: NSTextCheckingResult, group: Int) -> Int {
		guard
			let range = Range(match.range(at: group), in: string),
			!range.isEmpty
		else {
			return 0
		}

		return Int(string[range]) ?? 0
	}

	static func createPatchForHunk(at repositoryPath: String, file: FileChange, hunk: DiffHunk) -> String {
		var patch = "diff --git a/\(file.path) b/\(file.path)\n"

		// Add file headers based on status
		switch file.status {
		case .added,
		     .untracked:
			// `git apply` refuses a patch that creates a file without this line ("dev/null does not
			// exist in index"), so staging a hunk of a new file fails without it. A deletion needs no
			// matching "deleted file mode" line.
			patch += "new file mode \(newFileMode(at: repositoryPath, file: file))\n"
			patch += "--- /dev/null\n+++ b/\(file.path)\n"
		case .deleted:
			patch += "--- a/\(file.path)\n+++ /dev/null\n"
		default:
			patch += "--- a/\(file.path)\n+++ b/\(file.path)\n"
		}

		patch += hunk.header + "\n"

		// Add hunk lines, normalizing empty context lines
		for line in hunk.lines {
			let rawLine = (line.rawLine.isEmpty && line.type == .context) ? " " : line.rawLine
			patch += rawLine + "\n"
			if line.hasNoNewlineAtEndOfFile {
				patch += "\\ No newline at end of file\n"
			}
		}

		return patch
	}

	/// The mode `git apply` should give a file it is being asked to create. It takes the value
	/// literally, so claiming 100644 for an executable file stages it without its executable bit.
	///
	/// The working tree is the only source available: an untracked file is not in the index, and a
	/// staged addition only has a hunk to act on when `createUntrackedFileDiff` found it on disk.
	private static func newFileMode(at repositoryPath: String, file: FileChange) -> String {
		let fullPath = (repositoryPath as NSString).appendingPathComponent(file.path)
		return FileManager.default.isExecutableFile(atPath: fullPath) ? "100755" : "100644"
	}

}
