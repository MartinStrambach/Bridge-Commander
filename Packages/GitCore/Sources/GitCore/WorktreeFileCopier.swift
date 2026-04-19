import Foundation

public nonisolated enum WorktreeFileCopier {

	public struct Failure: Equatable, Sendable {
		public let path: String
		public let reason: String
	}

	public struct Result: Equatable, Sendable {
		public let copied: [String]
		public let missing: [String]
		public let failed: [Failure]

		public var hasWarnings: Bool { !missing.isEmpty || !failed.isEmpty }
	}

	/// Copies each of the given relative paths from the source repository into
	/// the new worktree. Missing paths are collected (not fatal); invalid paths
	/// (absolute, empty, or containing "..") are reported as failures.
	public static func copy(paths: [String], from sourceRepo: URL, to worktree: URL) -> Result {
		var copied: [String] = []
		var missing: [String] = []
		var failed: [Failure] = []

		let fm = FileManager.default

		for rawPath in paths {
			let path = rawPath.trimmingCharacters(in: .whitespaces)
			guard !path.isEmpty else {
				continue
			}

			if path.hasPrefix("/") || path.split(separator: "/").contains("..") {
				failed.append(.init(
					path: rawPath,
					reason: "invalid path (must be relative and not escape the repository)"
				))
				continue
			}

			let source = sourceRepo.appendingPathComponent(path)
			let dest = worktree.appendingPathComponent(path)

			guard fm.fileExists(atPath: source.path) else {
				missing.append(path)
				continue
			}

			do {
				let parent = dest.deletingLastPathComponent()
				if !fm.fileExists(atPath: parent.path) {
					try fm.createDirectory(at: parent, withIntermediateDirectories: true)
				}
				if fm.fileExists(atPath: dest.path) {
					failed.append(.init(path: rawPath, reason: "destination already exists"))
					continue
				}
				try fm.copyItem(at: source, to: dest)
				copied.append(path)
			}
			catch {
				failed.append(.init(path: rawPath, reason: error.localizedDescription))
			}
		}

		return Result(copied: copied, missing: missing, failed: failed)
	}
}
