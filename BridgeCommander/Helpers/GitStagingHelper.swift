import Foundation

nonisolated enum GitStagingHelper {
	// MARK: - Fetch File Changes

	static func fetchFileChanges(at path: String) async -> GitFileChanges {
		async let staged = fetchStagedFiles(at: path)
		async let unstaged = fetchUnstagedFiles(at: path)

		return await GitFileChanges(
			staged: staged,
			unstaged: unstaged
		)
	}

	// MARK: - Fetch Diff

	static func fetchFileDiff(
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
				["diff", "--cached", "--", file.path]
			}
			else {
				["diff", "--", file.path]
			}

		let result = await ProcessRunner.runGit(arguments: arguments, at: repositoryPath)
		guard result.success else {
			return nil
		}

		let diffOutput = result.outputString.trimmingCharacters(in: .whitespacesAndNewlines)

		// Check if empty output
		if diffOutput.isEmpty {
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

	static func stageFiles(at repositoryPath: String, filePaths: [String]) async throws {
		guard !filePaths.isEmpty else {
			return
		}

		// Build arguments with all file paths
		let arguments = ["add", "--"] + filePaths
		let result = await ProcessRunner.runGit(arguments: arguments, at: repositoryPath)
		guard result.success else {
			throw GitStagingError.commandFailed("Failed to stage files")
		}
	}

	// MARK: - Unstage Files

	static func unstageFiles(at repositoryPath: String, filePaths: [String]) async throws {
		guard !filePaths.isEmpty else {
			return
		}

		// Build arguments with all file paths
		let arguments = ["reset", "HEAD", "--"] + filePaths
		let result = await ProcessRunner.runGit(arguments: arguments, at: repositoryPath)
		guard result.success else {
			throw GitStagingError.commandFailed("Failed to unstage files")
		}
	}

	// MARK: - Stage Hunk

	static func stageHunk(
		at repositoryPath: String,
		file: FileChange,
		hunk: DiffHunk
	) async throws {
		// Create a patch with just this hunk
		let patch = createPatchForHunk(file: file, hunk: hunk)

		// Write patch to temporary file
		let tempDir = FileManager.default.temporaryDirectory
		let patchFile = tempDir.appendingPathComponent("hunk_\(UUID().uuidString).patch")

		try patch.write(to: patchFile, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: patchFile) }

		// Apply the patch to the index
		let arguments = ["apply", "--cached", patchFile.path]
		let result = await ProcessRunner.runGit(arguments: arguments, at: repositoryPath)
		guard result.success else {
			throw GitStagingError.commandFailed("Failed to stage hunk")
		}
	}

	// MARK: - Unstage Hunk

	static func unstageHunk(
		at repositoryPath: String,
		file: FileChange,
		hunk: DiffHunk
	) async throws {
		// Create a patch with just this hunk
		let patch = createPatchForHunk(file: file, hunk: hunk)

		// Write patch to temporary file
		let tempDir = FileManager.default.temporaryDirectory
		let patchFile = tempDir.appendingPathComponent("hunk_\(UUID().uuidString).patch")

		try patch.write(to: patchFile, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: patchFile) }

		// Apply the patch in reverse to the index
		let arguments = ["apply", "--cached", "--reverse", patchFile.path]
		let result = await ProcessRunner.runGit(arguments: arguments, at: repositoryPath)
		guard result.success else {
			throw GitStagingError.commandFailed("Failed to unstage hunk")
		}
	}

	// MARK: - Discard Hunk

	static func discardHunk(
		at repositoryPath: String,
		file: FileChange,
		hunk: DiffHunk
	) async throws {
		// Create a reverse patch of the hunk
		let patch = createPatchForHunk(file: file, hunk: hunk)

		// Write patch to temporary file
		let tempDir = FileManager.default.temporaryDirectory
		let patchFile = tempDir.appendingPathComponent("discard_hunk_\(UUID().uuidString).patch")

		try patch.write(to: patchFile, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: patchFile) }

		// Apply the patch in reverse to the working directory
		let arguments = ["apply", "-R", patchFile.path]
		let result = await ProcessRunner.runGit(arguments: arguments, at: repositoryPath)
		guard result.success else {
			throw GitStagingError.commandFailed("Failed to discard hunk")
		}
	}

	// MARK: - Discard File Changes

	static func discardFileChanges(at repositoryPath: String, filePath: String) async throws {
		// First check if file is tracked
		let lsFilesResult = await ProcessRunner.runGit(arguments: ["ls-files", "--", filePath], at: repositoryPath)
		let isTracked = lsFilesResult.success && !lsFilesResult.outputString
			.trimmingCharacters(in: .whitespacesAndNewlines)
			.isEmpty

		if isTracked {
			// For tracked files, restore from HEAD
			let result = await ProcessRunner.runGit(arguments: ["checkout", "HEAD", "--", filePath], at: repositoryPath)
			guard result.success else {
				throw GitStagingError.commandFailed("Failed to discard changes: \(filePath)")
			}
		}
		else {
			// For untracked files, just delete
			try await deleteUntrackedFile(at: repositoryPath, filePath: filePath)
		}
	}

	// MARK: - Delete Untracked File

	static func deleteUntrackedFile(at repositoryPath: String, filePath: String) async throws {
		let fullPath = (repositoryPath as NSString).appendingPathComponent(filePath)
		let fileURL = URL(fileURLWithPath: fullPath)

		do {
			try FileManager.default.removeItem(at: fileURL)
		}
		catch {
			throw GitStagingError.fileOperationFailed("Failed to delete file: \(error.localizedDescription)")
		}
	}

	// MARK: - Untracked File Diff

	private static func createUntrackedFileDiff(
		at repositoryPath: String,
		file: FileChange
	) async -> FileDiff? {
		let fullPath = (repositoryPath as NSString).appendingPathComponent(file.path)
		let fileURL = URL(fileURLWithPath: fullPath)

		// Check if file exists
		guard FileManager.default.fileExists(atPath: fullPath) else {
			return nil
		}

		// Check if it's a regular file (not directory or symlink)
		var isDirectory: ObjCBool = false
		guard
			FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDirectory),
			!isDirectory.boolValue
		else {
			return nil
		}

		// Try to read as text
		guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
			// If can't read as UTF-8, it's likely binary
			return FileDiff(fileChange: file, hunks: [], isBinary: true)
		}

		// Split into lines, preserving empty lines
		var lines = content.split(separator: "\n", omittingEmptySubsequences: false)

		// If file ends with newline, split adds an extra empty element - remove it
		if lines.last?.isEmpty == true {
			lines = lines.dropLast()
		}

		// Create diff lines (all additions)
		let diffLines = lines.map { "+" + $0 }
		let lineCount = diffLines.count

		// Create synthetic hunk
		let hunk = DiffHunk(
			header: "@@ -0,0 +1,\(lineCount) @@",
			oldStart: 0,
			oldCount: 0,
			newStart: 1,
			newCount: lineCount,
			lines: diffLines.map { DiffLine(rawLine: String($0)) }
		)

		return FileDiff(fileChange: file, hunks: [hunk], isBinary: false)
	}

	// MARK: - Private Helpers

	private static func fetchStagedFiles(at path: String) async -> [FileChange] {
		let result = await ProcessRunner.runGit(arguments: ["diff", "--cached", "--name-status"], at: path)
		guard result.success else {
			return []
		}

		return parseGitStatusOutput(result.outputString).sorted { $0.path < $1.path }
	}

	private static func fetchUnstagedFiles(at path: String) async -> [FileChange] {
		// Get modified/deleted files (unstaged)
		let diffResult = await ProcessRunner.runGit(arguments: ["diff", "--name-status"], at: path)
		let diffOutput = diffResult.success ? diffResult.outputString : ""

		// Get untracked files
		let untrackedResult = await ProcessRunner.runGit(
			arguments: ["ls-files", "--others", "--exclude-standard"],
			at: path
		)
		let untrackedOutput = untrackedResult.success ? untrackedResult.outputString : ""

		// Parse modified/deleted files
		var changes = parseGitStatusOutput(diffOutput)

		// Parse untracked files
		let untrackedLines = untrackedOutput.split(separator: "\n").map(String.init)
		for filePath in untrackedLines where !filePath.isEmpty {
			changes.append(FileChange(path: filePath, status: .untracked))
		}

		return changes.sorted { $0.path < $1.path }
	}

	private static func parseGitStatusOutput(_ output: String) -> [FileChange] {
		let lines = output.split(separator: "\n")
		var changes: [FileChange] = []

		for line in lines {
			let components = line.split(separator: "\t", maxSplits: 2)
			guard components.count >= 2 else {
				continue
			}

			let statusStr = String(components[0])
			let filePath = String(components[1])

			guard let status = FileChangeStatus(rawValue: statusStr) else {
				continue
			}

			// Handle renames
			if status == .renamed, components.count == 3 {
				let newPath = String(components[2])
				changes.append(FileChange(path: newPath, status: status, oldPath: filePath))
			}
			else {
				changes.append(FileChange(path: filePath, status: status))
			}
		}

		return changes
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
			// Collect all diff lines (skip metadata like "diff --git", "index", etc.)
			let diffLines = lines.filter { line in
				line.hasPrefix("+") || line.hasPrefix("-") || line.hasPrefix(" ")
			}

			guard !diffLines.isEmpty else {
				return []
			}

			// Create a synthetic hunk for the entire file
			let lineCount = diffLines.count
			let header: String
			let oldStart: Int
			let oldCount: Int
			let newStart: Int
			let newCount: Int

			if fileStatus == .added {
				header = "@@ -0,0 +1,\(lineCount) @@"
				oldStart = 0
				oldCount = 0
				newStart = 1
				newCount = lineCount
			}
			else {
				// deleted
				header = "@@ -1,\(lineCount) +0,0 @@"
				oldStart = 1
				oldCount = lineCount
				newStart = 0
				newCount = 0
			}

			let hunk = DiffHunk(
				header: header,
				oldStart: oldStart,
				oldCount: oldCount,
				newStart: newStart,
				newCount: newCount,
				lines: diffLines.map { DiffLine(rawLine: $0) }
			)

			return [hunk]
		}

		// Standard hunk parsing for modified files
		var currentHunkLines: [String] = []
		var currentHunkHeader: String?
		var hunkHeaderParts: (oldStart: Int, oldCount: Int, newStart: Int, newCount: Int)?

		for line in lines {
			if line.hasPrefix("@@") {
				// Save previous hunk if exists
				if
					let header = currentHunkHeader,
					let parts = hunkHeaderParts
				{
					let diffLines = currentHunkLines.map { DiffLine(rawLine: $0) }
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

				// Start new hunk
				currentHunkHeader = line
				hunkHeaderParts = parseHunkHeader(line)
				currentHunkLines = []
			}
			else if
				currentHunkHeader != nil,
				line.hasPrefix("+") || line.hasPrefix("-") || line.hasPrefix(" ")
			{
				currentHunkLines.append(line)
			}
		}

		// Save last hunk
		if
			let header = currentHunkHeader,
			let parts = hunkHeaderParts
		{
			let diffLines = currentHunkLines.map { DiffLine(rawLine: $0) }
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

		return hunks
	}

	private static func parseHunkHeader(_ header: String) -> (
		oldStart: Int, oldCount: Int, newStart: Int, newCount: Int
	) {
		// Parse: @@ -oldStart,oldCount +newStart,newCount @@
		let pattern = #"@@ -(\d+),?(\d*) \+(\d+),?(\d*) @@"#
		guard
			let regex = try? NSRegularExpression(pattern: pattern),
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
		var patch = ""

		// Add diff header
		patch += "diff --git a/\(file.path) b/\(file.path)\n"
		patch += "--- a/\(file.path)\n"
		patch += "+++ b/\(file.path)\n"

		// Add hunk
		patch += hunk.header + "\n"
		patch += hunk.lines.map(\.rawLine).joined(separator: "\n")
		patch += "\n"

		return patch
	}

}

// MARK: - Errors

enum GitStagingError: Error, LocalizedError {
	case commandFailed(String)
	case fileOperationFailed(String)

	var errorDescription: String? {
		switch self {
		case let .commandFailed(message),
		     let .fileOperationFailed(message):
			message
		}
	}
}
