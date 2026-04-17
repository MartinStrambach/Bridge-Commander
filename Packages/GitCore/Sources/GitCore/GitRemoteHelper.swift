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
	public static func getOriginRemote(at path: String) async -> GitRemote? {
		let result = await ProcessRunner.runGit(
			arguments: ["config", "--get", "remote.origin.url"],
			at: path
		)
		guard result.success else {
			return nil
		}
		return parse(result.trimmedOutput)
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
