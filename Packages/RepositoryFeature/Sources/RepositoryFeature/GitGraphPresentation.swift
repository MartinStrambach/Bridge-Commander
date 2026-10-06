import ComposableArchitecture
import Foundation
import GitCore
import GitGraphFeature
import Settings

extension GitGraphReducer.State {
	/// The commit graph for `path`, carrying the settings its "New Worktree from Commit…" needs —
	/// the same base path and copied files as the row's Create Worktree button. Copy paths are a
	/// group setting, keyed by the group's main repository, so a worktree's graph looks them up there.
	static func forRepository(path: String, name: String) -> Self {
		@Shared(.worktreeBasePath)
		var worktreeBasePath = "../worktrees"
		@Shared(.groupSettings)
		var groupSettings: [String: RepoGroupSettings] = [:]

		let groupRoot = GitDirectoryResolver.resolveMainRepositoryPath(at: path) ?? path
		return Self(
			repositoryPath: path,
			repositoryName: name,
			worktreeBasePath: worktreeBasePath,
			worktreeCopyPaths: groupSettings[groupRoot]?.worktreeCopyPaths ?? []
		)
	}
}
