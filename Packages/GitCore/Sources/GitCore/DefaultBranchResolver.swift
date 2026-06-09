import Foundation

/// Centralizes the "what counts as the default branch" decisions so the
/// semantics stay identical across the worktree picker, the Git Actions menu,
/// the Merge Master action, and the PR-fetch guard.
///
/// `configured` is a per-group setting (`RepoGroupSettings.defaultBranch`).
/// When it is empty, behavior falls back to the historical master/main rule.
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
}
