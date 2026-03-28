import Foundation

public struct BranchInfo: Equatable, Hashable {
	public let name: String
	public let existsLocally: Bool
	public let existsRemotely: Bool

	public var isRemoteOnly: Bool {
		existsRemotely && !existsLocally
	}

	public init(name: String, existsLocally: Bool, existsRemotely: Bool) {
		self.name = name
		self.existsLocally = existsLocally
		self.existsRemotely = existsRemotely
	}
}

public nonisolated enum GitBranchListHelper {

	/// Lists all local and remote branches in the repository with their location info
	/// - Parameter repositoryPath: The path to the Git repository
	/// - Returns: Array of BranchInfo objects
	public static func listBranchesWithInfo(at repositoryPath: String) async -> [BranchInfo] {
		let result = await ProcessRunner.runGit(
			arguments: [
				"for-each-ref",
				"--format=%(refname:short)",
				"refs/heads/",
				"refs/remotes/origin/"
			],
			at: repositoryPath
		)

		guard result.success else {
			return []
		}

		let allBranches = result.outputString
			.split(separator: "\n")
			.map { String($0) }
			.filter { $0 != "origin/HEAD" }

		// Separate local and remote branches
		var localBranches = Set<String>()
		var remoteBranches = Set<String>()

		for branch in allBranches {
			if branch.hasPrefix("origin/") {
				let name = branch.replacingOccurrences(of: "origin/", with: "")
				remoteBranches.insert(name)
			}
			else {
				localBranches.insert(branch)
			}
		}

		// Combine into BranchInfo objects
		let allBranchNames = localBranches.union(remoteBranches)
		return allBranchNames.map { name in
			BranchInfo(
				name: name,
				existsLocally: localBranches.contains(name),
				existsRemotely: remoteBranches.contains(name)
			)
		}
		.sorted { $0.name < $1.name }
	}
}
