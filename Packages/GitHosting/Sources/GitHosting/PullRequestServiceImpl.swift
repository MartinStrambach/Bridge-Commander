import Dependencies
import DependenciesMacros
import Foundation
import GitCore
import Sharing

@DependencyClient
public struct PullRequestClient: Sendable {
	/// `nil` means the provider confirmed there is no PR/MR for the branch;
	/// a thrown error means the answer is unknown (network/token/HTTP failure).
	public var fetchDetails: @Sendable (_ remote: GitRemote, _ branch: String) async throws -> PullRequestDetails?
}

extension PullRequestClient: DependencyKey {
	public static let liveValue = PullRequestClient(
		fetchDetails: { remote, branch in
			switch remote.host.lowercased() {
			case "github.com":
				@Shared(.githubToken)
				var token = ""
				return try await GitHubService.fetchPullRequest(
					owner: remote.owner,
					repo: remote.repo,
					branch: branch,
					token: token
				)

			case "gitlab.com":
				@Shared(.gitlabToken)
				var token = ""
				return try await GitLabService.fetchMergeRequest(
					projectPath: remote.projectPath,
					branch: branch,
					token: token
				)

			default:
				return nil
			}
		}
	)
}

extension PullRequestClient: TestDependencyKey {
	public static let testValue = PullRequestClient()
}
