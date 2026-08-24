import Foundation

public nonisolated enum GitHubService {
	private static let graphQLURL = "https://api.github.com/graphql"

	/// Fetches the branch's most recently created PR — state, draft flag, and unresolved
	/// review-thread count — in a single GraphQL request. REST would need two (it does not
	/// expose thread resolution at all).
	public static func fetchPullRequest(
		owner: String,
		repo: String,
		branch: String,
		token: String
	) async -> PullRequestDetails? {
		guard !token.isEmpty else {
			print("GitHubService: No token configured, skipping PR fetch")
			return nil
		}
		guard let url = URL(string: graphQLURL) else {
			return nil
		}

		// First 100 review threads only — enough in practice; the count is best-effort anyway.
		let query = """
		query($owner: String!, $name: String!, $branch: String!) {
			repository(owner: $owner, name: $name) {
				pullRequests(headRefName: $branch, first: 1, orderBy: {field: CREATED_AT, direction: DESC}) {
					nodes {
						url
						state
						isDraft
						reviewThreads(first: 100) {
							nodes { isResolved }
						}
					}
				}
			}
		}
		"""

		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.setValue("application/json", forHTTPHeaderField: "Accept")

		do {
			request.httpBody = try JSONEncoder().encode(
				GitHubGraphQLRequest(
					query: query,
					variables: .init(owner: owner, name: repo, branch: branch)
				)
			)

			print("GitHubService: Fetching PR for \(owner)/\(repo) on branch \(branch)")
			let (data, response) = try await URLSession.shared.data(for: request)

			guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
				let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
				print("GitHubService: Failed with status code \(statusCode)")
				return nil
			}

			let decoded = try JSONDecoder().decode(GitHubPullRequestResponse.self, from: data)
			guard let pullRequest = decoded.pullRequest else {
				print("GitHubService: No PR found for \(owner)/\(repo) on branch \(branch)")
				return nil
			}

			return PullRequestDetails(
				url: pullRequest.url,
				state: pullRequest.mappedState,
				provider: .github,
				unresolvedDiscussionsCount: pullRequest.unresolvedCount
			)
		}
		catch {
			print("GitHubService: Error: \(error)")
			return nil
		}
	}
}

private struct GitHubGraphQLRequest: Encodable {
	struct Variables: Encodable {
		let owner: String
		let name: String
		let branch: String
	}

	let query: String
	let variables: Variables
}

/// Internal (not private) so the response mapping is unit-testable from fixture JSON.
nonisolated struct GitHubPullRequestResponse: Decodable {
	struct DataContainer: Decodable {
		let repository: Repository?
	}

	struct Repository: Decodable {
		let pullRequests: PullRequests?
	}

	struct PullRequests: Decodable {
		let nodes: [PullRequest]?
	}

	struct PullRequest: Decodable {
		let url: String
		let state: String
		let isDraft: Bool?
		let reviewThreads: ReviewThreads?

		var mappedState: PullRequestState {
			switch state.uppercased() {
			case "MERGED":
				return .merged
			case "CLOSED":
				return .closed
			default:
				// "OPEN"
				if isDraft == true {
					return .draft
				}
				return .ready
			}
		}

		/// Number of unresolved threads among the fetched page (first 100). `nil` when missing.
		var unresolvedCount: Int? {
			guard let nodes = reviewThreads?.nodes else {
				return nil
			}
			return nodes.count { !$0.isResolved }
		}
	}

	struct ReviewThreads: Decodable {
		let nodes: [ReviewThread]?
	}

	struct ReviewThread: Decodable {
		let isResolved: Bool
	}

	let data: DataContainer?

	/// The branch's most recently created PR, or `nil` when none exists.
	var pullRequest: PullRequest? {
		data?.repository?.pullRequests?.nodes?.first
	}
}
