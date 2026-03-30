import Foundation
import ProcessExecution

public nonisolated enum GitStagingHelper {

	private static let hunkHeaderRegex = try? NSRegularExpression(
		pattern: #"@@ -(\d+),?(\d*) \+(\d+),?(\d*) @@"#
	)

	// MARK: - Fetch File Changes

	public static func fetchFileChanges(at path: String) async -> GitFileChanges {
		let status = await GitStatusDetector.getStatus(at: path)
		return GitFileChanges(
			staged: status.staged.sorted { $0.path < $1.path },
			unstaged: status.unstaged.sorted { $0.path < $1.path }
		)
	}

	// MARK: - Fetch Diff

	public static func fetchFileDiff(
		at repositoryPath: String,
		file: FileChange,
		isStaged: Bool
	) async -> FileDiff? {
		// For untracked files, create synthetic diff from file content
		if file.status == .untracked {
			return await createUntrackedFileDiff(at: repositoryPath, file: file)
		}

		// For added files in staged area, use synthetic diff
		if file.status == .added, isStaged {
			return await createUntrackedFileDiff(at: repositoryPath, file: file)
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

		// Check if binary file
		if diffOutput.contains("Binary files") {
			return FileDiff(fileChange: file, hunks: [], isBinary: true)
		}

		let hunks = parseDiffIntoHunks(diffOutput, fileStatus: file.status)
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

		// Use git checkout with multiple files in a single command
		let arguments = ["checkout", "HEAD", "--"] + filePaths
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
		file: FileChange
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
			return FileDiff(fileChange: file, hunks: [], isBinary: true)
		}

		var lines = content.split(separator: "\n", omittingEmptySubsequences: false)
		if lines.last?.isEmpty == true {
			lines = lines.dropLast()
		}

		let diffLines = lines.map { "+" + $0 }
		let lineCount = diffLines.count
		let hunkHeader = "@@ -0,0 +1,\(lineCount) @@"
		let hunk = DiffHunk(
			header: hunkHeader,
			oldStart: 0,
			oldCount: 0,
			newStart: 1,
			newCount: lineCount,
			lines: makeNumberedDiffLines(diffLines, hunkHeader: hunkHeader, oldStart: 0, newStart: 1)
		)

		return FileDiff(fileChange: file, hunks: [hunk], isBinary: false)
	}

	// MARK: - Private Helpers

	private static func applyPatch(
		at repositoryPath: String,
		file: FileChange,
		hunk: DiffHunk,
		arguments: [String],
		errorMessage: String
	) async throws {
		let patch = createPatchForHunk(file: file, hunk: hunk)
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

	private static func parseDiffIntoHunks(
		_ diffOutput: String,
		fileStatus: FileChangeStatus
	) -> [DiffHunk] {
		var hunks: [DiffHunk] = []
		let lines = diffOutput.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

		// For new/deleted files, git doesn't use @@ headers
		// Check if this is a file without traditional hunks
		let hasHunkHeaders = lines.contains { $0.hasPrefix("@@") }

		if !hasHunkHeaders, fileStatus == .added || fileStatus == .deleted {
			let diffLines = lines.compactMap { line -> String? in
				if line.hasPrefix("+") || line.hasPrefix("-") || line.hasPrefix(" ") {
					return line
				}
				else if line.isEmpty {
					return " "
				}
				return nil
			}

			guard !diffLines.isEmpty else {
				return []
			}

			let lineCount = diffLines.count
			let isAdded = fileStatus == .added
			let hunkHeader = isAdded ? "@@ -0,0 +1,\(lineCount) @@" : "@@ -1,\(lineCount) +0,0 @@"
			let oldStart = isAdded ? 0 : 1
			let newStart = isAdded ? 1 : 0
			let hunk = DiffHunk(
				header: hunkHeader,
				oldStart: oldStart,
				oldCount: isAdded ? 0 : lineCount,
				newStart: newStart,
				newCount: isAdded ? lineCount : 0,
				lines: makeNumberedDiffLines(diffLines, hunkHeader: hunkHeader, oldStart: oldStart, newStart: newStart)
			)

			return [hunk]
		}

		// Standard hunk parsing for modified files
		var currentHunkLines: [String] = []
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
				newStart: parts.newStart
			)
			hunks.append(
				DiffHunk(
					header: header,
					oldStart: parts.oldStart,
					oldCount: parts.oldCount,
					newStart: parts.newStart,
					newCount: parts.newCount,
					lines: diffLines
				)
			)
		}

		for line in lines {
			if line.hasPrefix("@@") {
				saveCurrentHunk()
				currentHunkHeader = line
				hunkHeaderParts = parseHunkHeader(line)
				currentHunkLines = []
			}
			else if currentHunkHeader != nil {
				if line.hasPrefix("+") || line.hasPrefix("-") || line.hasPrefix(" ") {
					currentHunkLines.append(line)
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
		newStart: Int
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
				newLineNumber: newNum
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

	private static func createPatchForHunk(file: FileChange, hunk: DiffHunk) -> String {
		var patch = "diff --git a/\(file.path) b/\(file.path)\n"

		// Add file headers based on status
		switch file.status {
		case .added,
		     .untracked:
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
		}

		return patch
	}

}
