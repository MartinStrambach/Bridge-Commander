import ComposableArchitecture
import Foundation
import GitCore
import Settings

public extension Notification.Name {
	/// Posted after a worktree was created from outside the repository list (an App Intent run
	/// by Siri, Shortcuts or Spotlight). `userInfo[ExternalWorktreeCreator.rootPathKey]` is the
	/// tracked root path, which is also the group id, so the list rescans just that group.
	static let worktreeCreatedExternally = Notification.Name("BridgeCommander.worktreeCreatedExternally")
}

/// Creates a worktree without the create-worktree dialog: the same git call, settings and file
/// copy as `CreateWorktreeButtonReducer`, but with the base branch picked the way the dialog
/// pre-selects it, since there is nobody to pick one.
public nonisolated enum ExternalWorktreeCreator {
	public static let rootPathKey = "rootPath"

	public struct Plan: Equatable, Sendable {
		public let branchName: String
		public let baseBranch: String
		public let createNewBranch: Bool
	}

	public enum PlanError: LocalizedError, Equatable {
		case emptyBranchName
		case noBranches
		case unknownBaseBranch(String)

		public var errorDescription: String? {
			switch self {
			case .emptyBranchName:
				"The branch name is empty."
			case .noBranches:
				"The repository has no branches to create a worktree from."
			case let .unknownBaseBranch(name):
				"There is no branch named \"\(name)\" to base the worktree on."
			}
		}
	}

	public struct Result: Sendable {
		public let worktreeURL: URL
		public let plan: Plan
		public let copyResult: WorktreeFileCopier.Result?
	}

	/// Decides what to hand `GitWorktreeCreator`. A name that already exists as a branch
	/// (locally or on origin) is checked out into the worktree rather than failing, because a
	/// spoken "create a worktree for feature-x" means the same thing whether or not feature-x
	/// exists yet. Otherwise a new branch is cut from `requestedBase`, or from the default branch.
	public static func plan(
		branchName rawName: String,
		requestedBase: String?,
		available: [String],
		configuredDefault: String
	) throws(PlanError) -> Plan {
		let branchName = GitBranchNameSanitizer.sanitize(rawName.trimmingCharacters(in: .whitespacesAndNewlines))
		guard !branchName.isEmpty else {
			throw .emptyBranchName
		}
		guard !available.isEmpty else {
			throw .noBranches
		}

		if let existing = available.first(where: { $0 == branchName }) {
			return Plan(branchName: existing, baseBranch: existing, createNewBranch: false)
		}

		let base: String
		if let requested = requestedBase?.trimmingCharacters(in: .whitespacesAndNewlines), !requested.isEmpty {
			guard let match = available.first(where: { $0.caseInsensitiveCompare(requested) == .orderedSame }) else {
				throw .unknownBaseBranch(requested)
			}
			base = match
		}
		else if let resolved = DefaultBranchResolver.resolveBaseBranch(configured: configuredDefault, available: available) {
			base = resolved
		}
		else {
			throw .noBranches
		}
		return Plan(branchName: branchName, baseBranch: base, createNewBranch: true)
	}

	/// Creates the worktree for the tracked repository at `repositoryPath` and posts
	/// `.worktreeCreatedExternally` so an open list picks it up.
	public static func create(
		repositoryPath: String,
		branchName: String,
		baseBranch: String?
	) async throws -> Result {
		@SharedReader(.worktreeBasePath) var worktreeBasePath = "../worktrees"
		@SharedReader(.groupSettings) var groupSettings: [String: RepoGroupSettings] = [:]
		let settings = groupSettings[repositoryPath]

		let branches = await GitBranchListHelper.listBranchesWithInfo(at: repositoryPath)
		let plan = try plan(
			branchName: branchName,
			requestedBase: baseBranch,
			available: branches.map(\.name),
			configuredDefault: settings?.defaultBranch ?? ""
		)

		let worktreeURL = try await GitWorktreeCreator.createWorktree(
			branchName: plan.branchName,
			baseBranch: plan.baseBranch,
			repositoryPath: repositoryPath,
			createNewBranch: plan.createNewBranch,
			worktreeBasePath: worktreeBasePath
		)
		let copyPaths = settings?.worktreeCopyPaths ?? []
		let copyResult = copyPaths.isEmpty
			? nil
			: WorktreeFileCopier.copy(paths: copyPaths, from: URL(fileURLWithPath: repositoryPath), to: worktreeURL)

		await MainActor.run {
			NotificationCenter.default.post(
				name: .worktreeCreatedExternally,
				object: nil,
				userInfo: [rootPathKey: repositoryPath]
			)
		}
		return Result(worktreeURL: worktreeURL, plan: plan, copyResult: copyResult)
	}
}
