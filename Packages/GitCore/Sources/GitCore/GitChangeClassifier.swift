import Foundation

// MARK: - Change

/// What a change on disk means for one repository (a main checkout or a linked worktree).
public nonisolated struct GitRepositoryChange: Equatable, Sendable {
	public struct Kind: OptionSet, Hashable, Sendable {
		public let rawValue: Int

		public init(rawValue: Int) {
			self.rawValue = rawValue
		}

		/// Branch, staged/unstaged counts, upstream or merge state may differ: `git status` again.
		public static let status = Kind(rawValue: 1 << 0)
		/// `refs/stash` moved.
		public static let stash = Kind(rawValue: 1 << 1)
		/// A linked worktree was added to or removed from the repository.
		public static let worktreeList = Kind(rawValue: 1 << 2)
	}

	/// The path the watch was started with, not the canonical one.
	public let repositoryPath: String
	public let kinds: Kind

	public init(repositoryPath: String, kinds: Kind) {
		self.repositoryPath = repositoryPath
		self.kinds = kinds
	}
}

// MARK: - Target

/// The three places one repository's state lives on disk, as canonical paths — FSEvents reports
/// resolved paths (`/private/var/…`, not `/var/…`), so these are compared against them directly.
nonisolated struct GitWatchTarget: Equatable, Sendable {
	/// The path the caller named the repository by, echoed back in `GitRepositoryChange`.
	let repositoryPath: String
	let workTree: String
	/// Per-worktree state: `HEAD`, `index`, `MERGE_HEAD`… (`.git/worktrees/<name>` for a linked one).
	let gitDirectory: String
	/// Shared by all worktrees: `refs/`, `packed-refs`, `config`, `worktrees/`.
	let commonGitDirectory: String

	init(repositoryPath: String, workTree: String, gitDirectory: String, commonGitDirectory: String) {
		self.repositoryPath = repositoryPath
		self.workTree = workTree
		self.gitDirectory = gitDirectory
		self.commonGitDirectory = commonGitDirectory
	}

	init?(repositoryPath: String) {
		guard var gitDirectory = GitDirectoryResolver.resolveGitDirectory(at: repositoryPath) else {
			return nil
		}

		// `worktree.useRelativePaths` (git 2.48+) writes the `gitdir:` line relative to the worktree.
		if !gitDirectory.hasPrefix("/") {
			gitDirectory = (repositoryPath as NSString).appendingPathComponent(gitDirectory)
		}
		let canonicalGitDirectory = Self.canonicalPath(gitDirectory)
		self.init(
			repositoryPath: repositoryPath,
			workTree: Self.canonicalPath(repositoryPath),
			gitDirectory: canonicalGitDirectory,
			commonGitDirectory: GitDirectoryResolver.commonGitDirectory(from: canonicalGitDirectory)
		)
	}

	/// `realpath(3)`, not `URL.resolvingSymlinksInPath()`: the latter strips `/private` from
	/// `/private/var/…`, which is exactly the form FSEvents reports.
	static func canonicalPath(_ path: String) -> String {
		guard let resolved = realpath(path, nil) else {
			return (path as NSString).standardizingPath
		}

		defer { free(resolved) }
		return String(cString: resolved)
	}
}

// MARK: - Event

nonisolated struct FileSystemEvent: Equatable, Sendable {
	let path: String
	/// The item itself appeared, disappeared or was renamed, rather than having its contents changed.
	let isCreatedOrRemoved: Bool
	/// FSEvents dropped events at or below `path`: anything there may have changed.
	let mustRescan: Bool

	init(path: String, isCreatedOrRemoved: Bool = false, mustRescan: Bool = false) {
		self.path = path
		self.isCreatedOrRemoved = isCreatedOrRemoved
		self.mustRescan = mustRescan
	}
}

// MARK: - Classifier

/// Sorts file system events into what they mean for each watched repository.
///
/// Inside a git directory only a handful of files carry what a row shows; everything else there
/// (`objects/`, `logs/`, lock files) is churn from the same operations. A working tree path is
/// returned as-is, for the caller to check against `.gitignore` — whether an edit changes
/// `git status` depends on rules this type does not read.
nonisolated enum GitChangeClassifier {
	struct Classification: Equatable {
		var kinds: [String: GitRepositoryChange.Kind] = [:]
		/// Changed paths in each repository's working tree, relative to it.
		var workingTreePaths: [String: [String]] = [:]
	}

	/// Entries of a per-worktree git directory whose change can move what a row shows.
	static let perWorktreeEntries: Set<String> = [
		"HEAD",
		"index",
		"MERGE_HEAD",
		"CHERRY_PICK_HEAD",
		"REVERT_HEAD",
		"rebase-merge",
		"rebase-apply",
		// `extensions.worktreeConfig`'s per-worktree settings, which can include an upstream.
		"config.worktree",
	]

	/// The file a reftable repository (`git init --ref-format=reftable`, the default from git 3.0)
	/// rewrites on every ref update. Its refs never touch `refs/`, `packed-refs` or `HEAD`, which
	/// are stubs there. New tables are written beside this file first, and the update takes effect
	/// when `tables.list.lock` is renamed over it — so this is the one event that means it is done.
	static let reftableCommitPoint = ["reftable", "tables.list"]

	static func classify(_ events: [FileSystemEvent], targets: [GitWatchTarget]) -> Classification {
		var result = Classification()
		for event in events {
			classify(event, targets: targets, into: &result)
		}
		return result
	}

	private static func classify(
		_ event: FileSystemEvent,
		targets: [GitWatchTarget],
		into result: inout Classification
	) {
		let path = event.path

		if event.mustRescan {
			// Events were lost; refresh whatever the lost subtree could have touched.
			for target in targets
				where isWithin(path, target.workTree) || isWithin(target.workTree, path)
				|| isWithin(path, target.commonGitDirectory) || isWithin(target.commonGitDirectory, path)
			{
				result.kinds[target.repositoryPath, default: []].insert(.status)
			}
			return
		}

		// Git directories first: a main checkout's `.git` sits inside its own working tree.
		if let commonGitDirectory = longest(targets.map(\.commonGitDirectory).filter { isWithin(path, $0) }) {
			classifyGitDirectoryEvent(event, commonGitDirectory: commonGitDirectory, targets: targets, into: &result)
			return
		}

		// The innermost working tree wins, so an edit in a worktree nested inside the main
		// checkout's folder belongs to the worktree.
		guard
			let owner = targets
				.filter({ path.hasPrefix($0.workTree + "/") })
				.max(by: { $0.workTree.count < $1.workTree.count })
		else {
			return
		}

		let relative = String(path.dropFirst(owner.workTree.count + 1))
		let components = relative.split(separator: "/")
		// A nested repository's (or submodule's) own git directory, a linked worktree's `.git`
		// file, and Finder's metadata are not part of what `git status` reports.
		guard !components.contains(".git"), components.last != ".DS_Store" else {
			return
		}

		result.workingTreePaths[owner.repositoryPath, default: []].append(relative)
	}

	private static func classifyGitDirectoryEvent(
		_ event: FileSystemEvent,
		commonGitDirectory: String,
		targets: [GitWatchTarget],
		into result: inout Classification
	) {
		let path = event.path
		guard !path.hasSuffix(".lock") else {
			// The write is not done yet; the rename onto the real name comes as its own event.
			return
		}

		// A linked worktree's `HEAD`/`index` live in its own `.git/worktrees/<name>`, which is
		// nested inside the main checkout's `.git` — so the innermost git directory owns the path.
		if
			let owner = targets
				.filter({ isWithin(path, $0.gitDirectory) })
				.max(by: { $0.gitDirectory.count < $1.gitDirectory.count })
		{
			let ownComponents = relativeComponents(of: path, under: owner.gitDirectory)
			// A linked worktree's own reftable holds its `HEAD`; the main checkout's is the shared
			// one, handled below with the other refs.
			let isOwnReftable = owner.gitDirectory != commonGitDirectory && ownComponents == reftableCommitPoint
			if let entry = ownComponents.first, perWorktreeEntries.contains(entry) || isOwnReftable {
				result.kinds[owner.repositoryPath, default: []].insert(.status)
				return
			}
		}

		let components = relativeComponents(of: path, under: commonGitDirectory)
		let sharing = targets.filter { $0.commonGitDirectory == commonGitDirectory }
		if components == reftableCommitPoint {
			// A reftable repository keeps every ref here — `HEAD`, branches and `refs/stash`
			// alike — so which one moved cannot be told from the path.
			for target in sharing {
				result.kinds[target.repositoryPath, default: []].formUnion([.status, .stash])
			}
			return
		}

		switch components.first {
		case "refs":
			// Branch tips are shared: a commit in one worktree, or a fetch, can move another's
			// upstream. One extra `git status` per worktree is cheaper than parsing which ref is whose.
			let kind: GitRepositoryChange.Kind = components == ["refs", "stash"] ? .stash : .status
			for target in sharing {
				result.kinds[target.repositoryPath, default: []].insert(kind)
			}

		case "packed-refs":
			for target in sharing {
				result.kinds[target.repositoryPath, default: []].insert(.status)
			}

		case "config" where components.count == 1:
			// `git branch -u`/`--unset-upstream` write only here, yet move the upstream `git status`
			// counts against. Branch settings are shared, and the file rarely changes.
			for target in sharing {
				result.kinds[target.repositoryPath, default: []].insert(.status)
			}

		case "worktrees"
			where (components.count == 2 && event.isCreatedOrRemoved)
			|| (components.count == 3 && components[2] == "gitdir"):
			// `git worktree add` creates `worktrees/<name>`, `remove`/`prune` deletes it, and
			// `move` (or `repair`) only rewrites its `gitdir` — the worktree's path. Other changes
			// inside an existing one are its own `HEAD`/`index`, handled above.
			let main = sharing.first { $0.gitDirectory == commonGitDirectory } ?? sharing.first
			if let main {
				result.kinds[main.repositoryPath, default: []].insert(.worktreeList)
			}

		default:
			break
		}
	}

	// MARK: - Paths

	/// The directories to hand FSEvents: every working tree and common git directory, minus any
	/// already covered by another (FSEvents watches recursively).
	static func watchRoots(for targets: [GitWatchTarget]) -> [String] {
		let candidates = Set(targets.flatMap { [$0.workTree, $0.commonGitDirectory] })
			.sorted { $0.count < $1.count }
		var roots: [String] = []
		for candidate in candidates where !roots.contains(where: { isWithin(candidate, $0) }) {
			roots.append(candidate)
		}
		return roots.sorted()
	}

	static func isWithin(_ path: String, _ directory: String) -> Bool {
		path == directory || path.hasPrefix(directory.hasSuffix("/") ? directory : directory + "/")
	}

	private static func relativeComponents(of path: String, under directory: String) -> [String] {
		guard path.count > directory.count else {
			return []
		}

		return path.dropFirst(directory.count + 1).split(separator: "/").map(String.init)
	}

	private static func longest(_ paths: [String]) -> String? {
		paths.max { $0.count < $1.count }
	}
}
