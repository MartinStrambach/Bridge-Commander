import Foundation
import ProcessExecution

/// A ref (branch, tag, HEAD) decorating a commit in the log
public struct GitCommitRef: Equatable, Hashable, Sendable {
	public enum Kind: Equatable, Hashable, Sendable {
		case localBranch
		case remoteBranch
		case tag
		case detachedHead
	}

	public let name: String
	public let kind: Kind

	/// True when HEAD points at this ref ("HEAD -> branch" in decorations)
	public let isHead: Bool

	public init(name: String, kind: Kind, isHead: Bool = false) {
		self.name = name
		self.kind = kind
		self.isHead = isHead
	}
}

/// A single commit from `git log`, with the parent hashes needed to draw a graph
public struct GitLogCommit: Equatable, Sendable, Identifiable {
	public let hash: String
	public let parents: [String]
	public let author: String
	public let date: Date
	public let refs: [GitCommitRef]
	public let subject: String

	public var id: String { hash }

	public var shortHash: String {
		String(hash.prefix(8))
	}

	public var isHead: Bool {
		refs.contains { $0.isHead }
	}

	public var isMerge: Bool {
		parents.count > 1
	}

	public init(
		hash: String,
		parents: [String],
		author: String,
		date: Date,
		refs: [GitCommitRef],
		subject: String
	) {
		self.hash = hash
		self.parents = parents
		self.author = author
		self.date = date
		self.refs = refs
		self.subject = subject
	}
}

public nonisolated enum GitLogHelper {
	private static let fieldSeparator: Character = "\u{1F}"
	private static let recordSeparator: Character = "\u{1E}"

	/// Loads commit history across all branches and tags in topological order
	/// (children before parents, as required by the graph layout).
	/// - Parameters:
	///   - repositoryPath: The path to the Git repository
	///   - limit: Maximum number of commits to load
	/// - Returns: Parsed commits, newest first
	public static func loadCommits(at repositoryPath: String, limit: Int) async throws -> [GitLogCommit] {
		let result = await ProcessRunner.runGit(
			arguments: [
				"log",
				"--branches",
				"--remotes",
				"--tags",
				"HEAD",
				"--topo-order",
				"--decorate=full",
				"--max-count=\(limit)",
				"--pretty=format:%H%x1f%P%x1f%an%x1f%ct%x1f%D%x1f%s%x1e"
			],
			at: repositoryPath
		)

		guard result.success else {
			throw GitError.logFailed(result.trimmedError)
		}

		return parse(logOutput: result.outputString)
	}

	/// Parses the raw `git log` output produced with the pretty format above
	/// (fields separated by 0x1F, records terminated by 0x1E).
	public static func parse(logOutput: String) -> [GitLogCommit] {
		logOutput.split(separator: recordSeparator).compactMap { record in
			let fields = record
				.trimmingCharacters(in: .whitespacesAndNewlines)
				.split(separator: fieldSeparator, omittingEmptySubsequences: false)
				.map(String.init)

			guard fields.count >= 6, !fields[0].isEmpty else {
				return nil
			}

			return GitLogCommit(
				hash: fields[0],
				parents: fields[1].split(separator: " ").map(String.init),
				author: fields[2],
				date: Date(timeIntervalSince1970: TimeInterval(fields[3]) ?? 0),
				refs: parseDecorations(fields[4]),
				subject: fields[5]
			)
		}
	}

	/// Parses `%D` decorations produced with `--decorate=full`,
	/// e.g. "HEAD -> refs/heads/main, refs/remotes/origin/main, tag: refs/tags/v1.0"
	static func parseDecorations(_ decorations: String) -> [GitCommitRef] {
		guard !decorations.isEmpty else {
			return []
		}

		return decorations
			.split(separator: ", ")
			.compactMap { entry in
				var name = String(entry)
				var isHead = false

				if name == "HEAD" {
					return GitCommitRef(name: "HEAD", kind: .detachedHead, isHead: true)
				}

				if name.hasPrefix("HEAD -> ") {
					isHead = true
					name = String(name.dropFirst("HEAD -> ".count))
				}

				if name.hasPrefix("tag: ") {
					name = String(name.dropFirst("tag: ".count))
				}

				if name.hasPrefix("refs/heads/") {
					return GitCommitRef(
						name: String(name.dropFirst("refs/heads/".count)),
						kind: .localBranch,
						isHead: isHead
					)
				}

				if name.hasPrefix("refs/remotes/") {
					let remoteName = String(name.dropFirst("refs/remotes/".count))

					// "origin/HEAD" is a symbolic ref duplicating the default branch — noise in the graph
					guard !remoteName.hasSuffix("/HEAD") else {
						return nil
					}

					return GitCommitRef(
						name: remoteName,
						kind: .remoteBranch,
						isHead: isHead
					)
				}

				if name.hasPrefix("refs/tags/") {
					return GitCommitRef(
						name: String(name.dropFirst("refs/tags/".count)),
						kind: .tag,
						isHead: isHead
					)
				}

				// Other refs (stash, notes, …) are not shown in the graph
				return nil
			}
	}
}
