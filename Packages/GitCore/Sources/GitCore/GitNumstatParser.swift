import Foundation

/// Parses `git diff --numstat -z` output into per-file added/removed line counts.
public nonisolated enum GitNumstatParser {

	/// Returns line stats keyed by file path (the new path for renames/copies).
	///
	/// `-z` record formats:
	/// - regular: `added\tremoved\tpath\0`
	/// - rename/copy: `added\tremoved\t\0oldPath\0newPath\0`
	///
	/// Binary files report `-\t-\t` and are omitted (stats unknown).
	public static func parse(_ output: String) -> [String: GitLineStats] {
		var stats: [String: GitLineStats] = [:]
		let fields = output.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)

		var index = 0
		while index < fields.count {
			let record = fields[index]
			index += 1

			let parts = record.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
			guard parts.count == 3 else {
				continue
			}

			let path: String
			if parts[2].isEmpty {
				// Rename/copy: paths follow as two separate NUL-terminated fields.
				guard index + 1 < fields.count else {
					break
				}

				path = fields[index + 1]
				index += 2
			}
			else {
				path = String(parts[2])
			}

			guard let added = Int(parts[0]), let removed = Int(parts[1]) else {
				continue // binary file ("-\t-")
			}

			stats[path] = GitLineStats(added: added, removed: removed)
		}

		return stats
	}
}
