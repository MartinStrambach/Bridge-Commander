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

	/// The parents the graph draws lines to. The same as `parents` for the whole history; a
	/// search that cannot have git rewrite parents keeps only the ones it also lists (see
	/// `GitLogSearch.rewritesParents`), so `isMerge` still describes the commit itself.
	public let graphParents: [String]
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
		subject: String,
		graphParents: [String]? = nil
	) {
		self.hash = hash
		self.parents = parents
		self.graphParents = graphParents ?? parents
		self.author = author
		self.date = date
		self.refs = refs
		self.subject = subject
	}
}

/// What the commit graph is narrowed to: the commits whose message, author, hash, changed paths or
/// changed content match a query.
public struct GitLogSearch: Equatable, Hashable, Sendable {
	public enum Field: String, CaseIterable, Equatable, Hashable, Sendable {
		/// The full commit message (`--grep`)
		case message
		/// Author name or email (`--author`)
		case author
		/// A full or abbreviated hash, resolved by `git rev-parse`
		case hash
		/// Any changed path containing the query (`-- <pathspec>`)
		case path
		/// Commits that add or remove the query text (`-S`)
		case content
	}

	public let field: Field
	public let query: String

	/// Nil for a blank query, which narrows nothing.
	public init?(field: Field, query: String) {
		let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else {
			return nil
		}

		self.field = field
		self.query = trimmed
	}

	/// Whether git rewrites each result's parents to its nearest ancestors in the results. It does
	/// only for a pathspec: history simplification is the one filter its parent rewriting follows.
	/// `--grep`, `--author` and `-S` hide commits but leave every parent pointing at them.
	public var rewritesParents: Bool {
		field == .path
	}
}

public nonisolated enum GitLogHelper {
	private static let fieldSeparator: Character = "\u{1F}"
	private static let recordSeparator: Character = "\u{1E}"

	private static let prettyFormat = "--pretty=format:%H%x1f%P%x1f%an%x1f%ct%x1f%D%x1f%s%x1e"

	/// Loads commit history across all branches and tags in topological order
	/// (children before parents, as required by the graph layout).
	/// - Parameters:
	///   - repositoryPath: The path to the Git repository
	///   - limit: Maximum number of commits to load
	///   - search: Narrows the history to the commits matching it; nil loads all of it
	/// - Returns: Parsed commits, newest first
	public static func loadCommits(
		at repositoryPath: String,
		limit: Int,
		search: GitLogSearch? = nil
	) async throws -> [GitLogCommit] {
		if let search, search.field == .hash {
			return try await loadCommit(named: search.query, at: repositoryPath)
		}

		let result = await ProcessRunner.runGit(
			arguments: logArguments(limit: limit, search: search),
			at: repositoryPath
		)

		guard result.success else {
			throw GitError.logFailed(result.trimmedError)
		}

		let commits = parse(logOutput: result.outputString)
		guard let search, !search.rewritesParents else {
			return commits
		}

		return pruningUnlistedGraphParents(commits)
	}

	/// The `git log` invocation for `loadCommits`, minus the hash search, which is not a log filter.
	static func logArguments(limit: Int, search: GitLogSearch?) -> [String] {
		var arguments = [
			"log",
			"--branches",
			"--remotes",
			"--tags",
			"HEAD",
			"--topo-order",
			"--decorate=full",
			"--max-count=\(limit)",
			prettyFormat
		]

		guard let search else {
			return arguments
		}

		// Case-insensitive throughout, and literal: a query is typed text, and something like
		// "fix(" is not a valid regular expression. `-S` is literal already; `-i` reaches it too.
		switch search.field {
		case .message:
			arguments += ["--regexp-ignore-case", "--fixed-strings", "--grep=\(search.query)"]
		case .author:
			arguments += ["--regexp-ignore-case", "--fixed-strings", "--author=\(search.query)"]
		case .content:
			arguments += ["--regexp-ignore-case", "-S\(search.query)"]
		case .path:
			// `--parents` turns on parent rewriting: each listed commit's parents become its
			// nearest listed ancestors, so the filtered graph is still a connected file history.
			arguments += ["--parents", "--"] + pathspecs(for: search.query)
		case .hash:
			break
		}
		return arguments
	}

	/// Pathspecs matching every path that contains `query`, case-insensitively, at any depth.
	///
	/// Three of them because a glob matches whole paths only: `**/*query*` finds a file named like
	/// the query (or a path ending in it), `**/*query*/**` everything under a directory named like
	/// it, and the plain `icase` one a path given exactly from the repository root.
	static func pathspecs(for query: String) -> [String] {
		let trimmed = query.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
		return [
			":(icase)\(trimmed)",
			":(glob,icase)**/*\(trimmed)*",
			":(glob,icase)**/*\(trimmed)*/**"
		]
	}

	/// The commit `name` resolves to (a full or abbreviated hash, or any other revision), alone.
	/// An unknown or ambiguous name matches nothing rather than failing.
	private static func loadCommit(named name: String, at repositoryPath: String) async throws -> [GitLogCommit] {
		let resolved = await ProcessRunner.runGit(
			arguments: ["rev-parse", "--verify", "--quiet", "--end-of-options", "\(name)^{commit}"],
			at: repositoryPath
		)

		guard resolved.success else {
			return []
		}

		let result = await ProcessRunner.runGit(
			arguments: ["log", "--no-walk", "--decorate=full", prettyFormat, resolved.trimmedOutput],
			at: repositoryPath
		)

		guard result.success else {
			throw GitError.logFailed(result.trimmedError)
		}

		return pruningUnlistedGraphParents(parse(logOutput: result.outputString))
	}

	/// Drops every graph parent that is not itself in `commits`. Without parent rewriting most
	/// parents of a search result are commits that did not match, and the layout would keep a lane
	/// open for each one down to the bottom of the list. A line that is left joins a commit to its
	/// direct parent, which both matched.
	static func pruningUnlistedGraphParents(_ commits: [GitLogCommit]) -> [GitLogCommit] {
		let listed = Set(commits.map(\.hash))
		return commits.map { commit in
			GitLogCommit(
				hash: commit.hash,
				parents: commit.parents,
				author: commit.author,
				date: commit.date,
				refs: commit.refs,
				subject: commit.subject,
				graphParents: commit.graphParents.filter(listed.contains)
			)
		}
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
