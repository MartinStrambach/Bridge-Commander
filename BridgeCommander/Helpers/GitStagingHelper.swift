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

	static func stageFiles(at repositoryPath: String, filePaths: [String]) async throws {
		guard !filePaths.isEmpty else {
			return
		}

		// Build arguments with all file paths
		let arguments = ["add", "--"] + filePaths
		let result = await ProcessRunner.runGit(arguments: arguments, at: repositoryPath)
		guard result.success else {
			throw GitError.stagingFailed("Failed to stage files")
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
			throw GitError.stagingFailed("Failed to unstage files")
		}
	}

	// MARK: - Stage Hunk

	static func stageHunk(
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

	static func unstageHunk(
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

	static func discardHunk(
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

	static func discardFileChanges(at repositoryPath: String, filePaths: [String]) async throws {
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

	static func deleteConflictedFiles(at repositoryPath: String, filePaths: [String]) async throws {
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

	static func commit(at path: String, message: String) async throws {
		let result = await ProcessRunner.runGit(arguments: ["commit", "-m", message], at: path)
		guard result.success else {
			let errMsg = result.errorString.isEmpty ? result.outputString : result.errorString
			throw GitError.commitFailed(errMsg)
		}
	}

	// MARK: - Delete Untracked Files

	static func deleteUntrackedFiles(at repositoryPath: String, filePaths: [String]) async throws {
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

		// Get unmerged/conflicted files
		let unmergedFiles = await fetchUnmergedFiles(at: path)
		let unmergedPaths = Set(unmergedFiles.map(\.path))

		// Parse modified/deleted files, skipping those already in unmerged list
		var changes = parseGitStatusOutput(diffOutput).filter { !unmergedPaths.contains($0.path) }

		// Parse untracked files
		let untrackedLines = untrackedOutput.split(separator: "\n").map(String.init)
		for filePath in untrackedLines where !filePath.isEmpty {
			changes.append(FileChange(path: filePath, status: .untracked))
		}

		// Append conflicted files
		changes.append(contentsOf: unmergedFiles)

		return changes.sorted { $0.path < $1.path }
	}

	private static func fetchUnmergedFiles(at path: String) async -> [FileChange] {
		let result = await ProcessRunner.runGit(arguments: ["ls-files", "--unmerged"], at: path)
		guard result.success else {
			return []
		}

		// Each line: <mode> <hash> <stage> <tab> <path>
		// Multiple stage entries per file — collect unique paths
		var seen = Set<String>()
		var changes: [FileChange] = []
		for line in result.outputString.split(separator: "\n") {
			let parts = line.split(separator: "\t", maxSplits: 1)
			guard parts.count == 2 else {
				continue
			}

			let filePath = String(parts[1])
			guard !filePath.isEmpty, seen.insert(filePath).inserted else {
				continue
			}

			changes.append(FileChange(path: filePath, status: .conflicted))
		}
		return changes
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
			let hunk = DiffHunk(
				header: isAdded ? "@@ -0,0 +1,\(lineCount) @@" : "@@ -1,\(lineCount) +0,0 @@",
				oldStart: isAdded ? 0 : 1,
				oldCount: isAdded ? 0 : lineCount,
				newStart: isAdded ? 1 : 0,
				newCount: isAdded ? lineCount : 0,
				lines: diffLines.map { DiffLine(rawLine: $0) }
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
