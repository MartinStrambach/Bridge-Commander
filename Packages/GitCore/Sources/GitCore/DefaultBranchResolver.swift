import Foundation

/// Centralizes the "what counts as the default branch" decisions so the
/// semantics stay identical across the worktree picker, the Git Actions menu,
/// the Merge Master action, and the PR-fetch guard.
///
/// `configured` is a per-group setting (`RepoGroupSettings.defaultBranch`).
/// When it is empty, behavior falls back to the historical master/main rule,
/// or — where the remote is known — to what `origin/HEAD` advertises.
public nonisolated enum DefaultBranchResolver {
	/// Whether `branch` should be treated as the repository's default branch.
	/// Empty `configured` matches "master" or "main"; otherwise matches the
	/// configured name exactly. Comparison is case-insensitive.
	public static func isDefaultBranch(_ branch: String, configured: String) -> Bool {
		let branch = branch.lowercased()
		let configured = configured.trimmingCharacters(in: .whitespacesAndNewlines)
		if configured.isEmpty {
			return branch == "master" || branch == "main"
		}
		return branch == configured.lowercased()
	}

	/// The branch to pre-select from `available`. Prefers the configured branch
	/// when present, then "master", then "main", then the first available
	/// branch. Returns nil when `available` is empty.
	public static func resolveBaseBranch(configured: String, available: [String]) -> String? {
		let configured = configured.trimmingCharacters(in: .whitespacesAndNewlines)
		if !configured.isEmpty,
		   let match = available.first(where: { $0.caseInsensitiveCompare(configured) == .orderedSame }) {
			return match
		}
		if let master = available.first(where: { $0.caseInsensitiveCompare("master") == .orderedSame }) {
			return master
		}
		if let main = available.first(where: { $0.caseInsensitiveCompare("main") == .orderedSame }) {
			return main
		}
		return available.first
	}

	/// The remote branch that "merge default branch" should fetch and merge.
	///
	/// A non-empty `configured` value always wins, verbatim, so a mistyped setting
	/// fails loudly at fetch time instead of silently merging something else.
	/// Otherwise the remote's advertised default (`origin/HEAD`, passed in as
	/// `originHead`, with or without the `origin/` prefix) is used, then "master"
	/// or "main" if either exists among `remoteBranches`, then "master" as the
	/// historical last resort.
	public static func resolveRemoteDefaultBranch(
		configured: String,
		originHead: String?,
		remoteBranches: [String]
	) -> String {
		let configured = configured.trimmingCharacters(in: .whitespacesAndNewlines)
		if !configured.isEmpty {
			return configured
		}
		if let originHead = originHead?.trimmingCharacters(in: .whitespacesAndNewlines), !originHead.isEmpty {
			let prefix = "origin/"
			return originHead.hasPrefix(prefix) ? String(originHead.dropFirst(prefix.count)) : originHead
		}
		if let master = remoteBranches.first(where: { $0.caseInsensitiveCompare("master") == .orderedSame }) {
			return master
		}
		if let main = remoteBranches.first(where: { $0.caseInsensitiveCompare("main") == .orderedSame }) {
			return main
		}
		return "master"
	}
}
