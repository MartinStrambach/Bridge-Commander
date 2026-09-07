import Foundation
import ProcessExecution

/// Reads what a single commit changed. Every command here only inspects objects that are already
/// in the repository, so browsing commits never touches the index, the working tree or HEAD.
///
/// A merge commit is diffed against its first parent (`--first-parent`), the side its branch was
/// merged into — git prints no diff at all for a merge otherwise. A root commit has no parent and
/// shows every file as an addition.
public nonisolated enum GitCommitDiffHelper {

	private static let commonDiffArguments = ["--format=", "-M", "--first-parent"]

	// MARK: - Fetch File Changes

	/// The files a commit changed, sorted by path, with added/removed line counts.
	public static func fetchFileChanges(at repositoryPath: String, commitHash: String) async -> [FileChange] {
		async let nameStatusTask = run(options: ["--name-status", "-z"], at: repositoryPath, commitHash: commitHash)
		async let numstatTask = run(options: ["--numstat", "-z"], at: repositoryPath, commitHash: commitHash)

		let (nameStatus, numstat) = await (nameStatusTask, numstatTask)
		guard let nameStatus else {
			return []
		}

		let stats = numstat.map(GitNumstatParser.parse) ?? [:]

		return parseNameStatus(nameStatus)
			.sorted { $0.path < $1.path }
			.map { $0.withLineStats(stats[$0.path]) }
	}

	// MARK: - Fetch Diff

	/// The diff of one file in a commit, or nil when git reported no change for it.
	public static func fetchFileDiff(
		at repositoryPath: String,
		commitHash: String,
		file: FileChange
	) async -> FileDiff? {
		// A rename is only recognisable when both sides are inside the pathspec; limiting to the
		// new path alone would make git report the file as a plain addition.
		let paths: [String] =
			if file.status == .renamed || file.status == .copied, let oldPath = file.oldPath {
				[oldPath, file.path]
			}
			else {
				[file.path]
			}

		guard
			let diffOutput = await run(options: [], at: repositoryPath, commitHash: commitHash, paths: paths)
		else {
			return nil
		}
		guard !diffOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
			return nil
		}

		if GitBinaryDiffDetector.isBinaryDiff(diffOutput) {
			let imageDiff = await GitImageDiffLoader.load(at: repositoryPath, file: file, commitHash: commitHash)
			return FileDiff(fileChange: file, hunks: [], isBinary: true, imageDiff: imageDiff)
		}

		return FileDiff(
			fileChange: file,
			hunks: GitDiffHunkParser.parse(diffOutput, fileStatus: file.status),
			isBinary: false
		)
	}

	// MARK: - Name Status Parsing

	/// Parses `git show --name-status -z` output.
	///
	/// `-z` record formats:
	/// - regular: `status\0path\0`
	/// - rename/copy: `Rnnn\0oldPath\0newPath\0` (`nnn` is the similarity score)
	static func parseNameStatus(_ output: String) -> [FileChange] {
		var changes: [FileChange] = []
		let fields = output.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)

		var index = 0
		while index < fields.count {
			let statusField = fields[index]
			index += 1

			guard
				let letter = statusField.first,
				let status = FileChangeStatus(rawValue: String(letter))
			else {
				continue // trailing empty field, or a status this app does not model
			}

			if status == .renamed || status == .copied {
				// Both paths follow as separate NUL-terminated fields.
				guard index + 1 < fields.count else {
					break
				}

				let oldPath = fields[index]
				let newPath = fields[index + 1]
				index += 2

				guard !oldPath.isEmpty, !newPath.isEmpty else {
					continue
				}

				changes.append(FileChange(path: newPath, status: status, oldPath: oldPath))
			}
			else {
				guard index < fields.count else {
					break
				}

				let path = fields[index]
				index += 1

				guard !path.isEmpty else {
					continue
				}

				changes.append(FileChange(path: path, status: status))
			}
		}

		return changes
	}

	// MARK: - Private Helpers

	/// Runs `git show` for the commit with the shared diff options, returning nil on failure.
	private static func run(
		options: [String],
		at repositoryPath: String,
		commitHash: String,
		paths: [String] = []
	) async -> String? {
		var arguments = ["show"] + commonDiffArguments + options + [commitHash]
		if !paths.isEmpty {
			arguments += ["--"] + paths
		}

		let result = await ProcessRunner.runGit(arguments: arguments, at: repositoryPath)
		return result.success ? result.outputString : nil
	}
}
