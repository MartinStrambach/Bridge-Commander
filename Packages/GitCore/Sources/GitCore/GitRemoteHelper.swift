import Foundation
import ProcessExecution

public nonisolated struct GitRemote: Equatable, Sendable {
	public let host: String
	public let owner: String
	public let repo: String

	public init(host: String, owner: String, repo: String) {
		self.host = host
		self.owner = owner
		self.repo = repo
	}

	/// Owner/repo joined with a slash — used as GitLab's URL-encoded project path input.
	public var projectPath: String {
		"\(owner)/\(repo)"
	}
}

public nonisolated enum GitRemoteHelper {
	/// Git config lives in the common git directory, so every worktree of a repository
	/// shares one origin remote — and it effectively never changes. Successful lookups
	/// are therefore cached for the app's lifetime and concurrent lookups coalesced,
	/// instead of spawning one `git config` process per row on every refresh.
	private static let cache = OriginRemoteCache()

	public static func getOriginRemote(at path: String) async -> GitRemote? {
		await cache.remote(at: path)
	}

	static func parse(_ url: String) -> GitRemote? {
		let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else {
			return nil
		}

		// SSH form: git@host:owner/repo(.git)
		if trimmed.hasPrefix("git@") {
			let withoutPrefix = String(trimmed.dropFirst("git@".count))
			guard let colonIdx = withoutPrefix.firstIndex(of: ":") else {
				return nil
			}
			let host = String(withoutPrefix[..<colonIdx])
			let pathPart = String(withoutPrefix[withoutPrefix.index(after: colonIdx)...])
			return parseOwnerRepo(host: host, path: pathPart)
		}

		// HTTPS / HTTP / ssh:// / git://
		if let components = URLComponents(string: trimmed), let host = components.host {
			return parseOwnerRepo(host: host, path: components.path)
		}

		return nil
	}

	private static func parseOwnerRepo(host: String, path: String) -> GitRemote? {
		var path = path
		while path.hasPrefix("/") {
			path.removeFirst()
		}
		if path.hasSuffix(".git") {
			path.removeLast(".git".count)
		}
		let parts = path.split(separator: "/", omittingEmptySubsequences: true)
		guard parts.count >= 2 else {
			return nil
		}
		let owner = String(parts[0])
		let repo = parts.dropFirst().joined(separator: "/")
		guard !owner.isEmpty, !repo.isEmpty else {
			return nil
		}
		return GitRemote(host: host, owner: owner, repo: repo)
	}
}

// MARK: -

/// Caches origin remotes keyed by the repository's common git directory, so all
/// worktrees of one repository share a single cached value. Only successful lookups
/// are cached — a repo without an origin remote keeps retrying, same as before.
private actor OriginRemoteCache {
	private var cached: [String: GitRemote] = [:]
	private var inFlight: [String: Task<GitRemote?, Never>] = [:]

	func remote(at path: String) async -> GitRemote? {
		let key = GitDirectoryResolver.resolveCommonGitDirectory(at: path) ?? path
		if let hit = cached[key] {
			return hit
		}
		if let existing = inFlight[key] {
			return await existing.value
		}

		let task = Task<GitRemote?, Never> { @concurrent in
			let result = await ProcessRunner.runGit(
				arguments: ["config", "--get", "remote.origin.url"],
				at: path
			)
			guard result.success else {
				return nil
			}
			return GitRemoteHelper.parse(result.trimmedOutput)
		}
		inFlight[key] = task

		let remote = await task.value
		if let remote {
			cached[key] = remote
		}
		// Only clear our own entry — a waiter resuming late must not evict a newer in-flight task.
		if inFlight[key] == task {
			inFlight[key] = nil
		}
		return remote
	}
}
