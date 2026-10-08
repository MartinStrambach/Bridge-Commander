import ActivityLog
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
	/// The remote's open PRs/MRs, those from forks included, most recently updated
	/// first. Empty for a host that is neither github.com nor gitlab.com.
	public var listOpen: @Sendable (_ remote: GitRemote) async throws -> [OpenPullRequest]
}

extension PullRequestClient: DependencyKey {
	public static let liveValue = PullRequestClient(
		fetchDetails: { remote, branch in
			try await ActivityLog.shared.recordingErrors(
				"Pull request of \(remote.host)/\(remote.projectPath) on \(branch)",
				unless: isMissingToken
			) {
				try await fetchDetails(remote: remote, branch: branch)
			}
		},
		listOpen: { remote in
			try await ActivityLog.shared.recordingErrors(
				"Open pull requests of \(remote.host)/\(remote.projectPath)",
				unless: isMissingToken
			) {
				try await listOpen(remote: remote)
			}
		}
	)

	/// Every refresh asks for every row's PR/MR, so a provider without a token would fill the log.
	private static func isMissingToken(_ error: any Error) -> Bool {
		if case GitHostingError.missingToken = error {
			return true
		}
		return false
	}

	private static func fetchDetails(remote: GitRemote, branch: String) async throws -> PullRequestDetails? {
		// Tokens saved before Settings started trimming may still carry pasted
		// whitespace; a dirty Bearer header fails every request with a silent 401.
		switch remote.host.lowercased() {
		case "github.com":
			@Shared(.githubToken)
			var token = ""
			return try await GitHubService.fetchPullRequest(
				owner: remote.owner,
				repo: remote.repo,
				branch: branch,
				token: token.trimmingCharacters(in: .whitespacesAndNewlines)
			)

		case "gitlab.com":
			@Shared(.gitlabToken)
			var token = ""
			return try await GitLabService.fetchMergeRequest(
				projectPath: remote.projectPath,
				branch: branch,
				token: token.trimmingCharacters(in: .whitespacesAndNewlines)
			)

		default:
			return nil
		}
	}

	private static func listOpen(remote: GitRemote) async throws -> [OpenPullRequest] {
		switch remote.host.lowercased() {
		case "github.com":
			@Shared(.githubToken)
			var token = ""
			return try await GitHubService.fetchOpenPullRequests(
				owner: remote.owner,
				repo: remote.repo,
				token: token.trimmingCharacters(in: .whitespacesAndNewlines)
			)

		case "gitlab.com":
			@Shared(.gitlabToken)
			var token = ""
			return try await GitLabService.fetchOpenMergeRequests(
				projectPath: remote.projectPath,
				token: token.trimmingCharacters(in: .whitespacesAndNewlines)
			)

		default:
			return []
		}
	}
}

extension PullRequestClient: TestDependencyKey {
	public static let testValue = PullRequestClient()
}
