import Dependencies
import DependenciesMacros
import Foundation
import GitCore
import Sharing

@DependencyClient
public struct PullRequestClient: Sendable {
	public var fetchDetails: @Sendable (_ remote: GitRemote, _ branch: String) async -> PullRequestDetails?
}

extension PullRequestClient: DependencyKey {
	public static let liveValue = PullRequestClient(
		fetchDetails: { remote, branch in
			switch remote.host.lowercased() {
			case "github.com":
				@Shared(.githubToken)
				var token = ""
				return await GitHubService.fetchPullRequest(
					owner: remote.owner,
					repo: remote.repo,
					branch: branch,
					token: token
				)

			case "gitlab.com":
				@Shared(.gitlabToken)
				var token = ""
				return await GitLabService.fetchMergeRequest(
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
