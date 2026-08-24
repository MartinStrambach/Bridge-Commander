import Foundation

public nonisolated enum GitHubService {
	private static let baseURL = "https://api.github.com"

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
		guard
			let encodedBranch = branch.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
			let encodedOwner = owner.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
		else {
			return nil
		}

		let urlString =
			"\(baseURL)/repos/\(owner)/\(repo)/pulls?head=\(encodedOwner):\(encodedBranch)&state=all&per_page=1&sort=created&direction=desc"
		guard let url = URL(string: urlString) else {
			return nil
		}

		var request = URLRequest(url: url)
		request.httpMethod = "GET"
		request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
		request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
		request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

		do {
			print("GitHubService: Fetching \(urlString)")
			let (data, response) = try await URLSession.shared.data(for: request)

			guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
				let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
				print("GitHubService: Failed with status code \(statusCode)")
				return nil
			}

			let pulls = try JSONDecoder().decode([GitHubPullRequest].self, from: data)
			guard let first = pulls.first else {
				print("GitHubService: No PR found for \(owner)/\(repo) on branch \(branch)")
				return nil
			}

			return PullRequestDetails(
				url: first.html_url,
				state: first.mappedState,
				provider: .github,
				number: first.number
			)
		}
		catch {
			print("GitHubService: Error: \(error)")
			return nil
		}
	}

	/// Best-effort fetch of the PR's unresolved review-thread count. The REST API does not
	/// expose thread resolution, so this uses GraphQL. Returns `nil` on any failure.
	public static func fetchUnresolvedReviewThreadCount(
		owner: String,
		repo: String,
		number: Int,
		token: String
	) async -> Int? {
		guard !token.isEmpty, let url = URL(string: "\(baseURL)/graphql") else {
			return nil
		}

		// First 100 threads only — enough in practice; counting is best-effort anyway.
		let query = """
		query($owner: String!, $name: String!, $number: Int!) {
			repository(owner: $owner, name: $name) {
				pullRequest(number: $number) {
					reviewThreads(first: 100) {
						nodes { isResolved }
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
					variables: .init(owner: owner, name: repo, number: number)
				)
			)

			print("GitHubService: Fetching review threads for \(owner)/\(repo)#\(number)")
			let (data, response) = try await URLSession.shared.data(for: request)

			guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
				let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
				print("GitHubService: Review threads fetch failed with status code \(statusCode)")
				return nil
			}

			return try JSONDecoder().decode(GitHubReviewThreadsResponse.self, from: data).unresolvedCount
		}
		catch {
			print("GitHubService: Review threads fetch error: \(error)")
			return nil
		}
	}
}

private struct GitHubPullRequest: Decodable {
	let number: Int
	let html_url: String
	let state: String
	let draft: Bool?
	let merged_at: String?

	var mappedState: PullRequestState {
		if merged_at != nil {
			return .merged
		}
		if state == "closed" {
			return .closed
		}
		if draft == true {
			return .draft
		}
		return .ready
	}
}

private struct GitHubGraphQLRequest: Encodable {
	struct Variables: Encodable {
		let owner: String
		let name: String
		let number: Int
	}

	let query: String
	let variables: Variables
}

/// Internal (not private) so the count derivation is unit-testable from fixture JSON.
nonisolated struct GitHubReviewThreadsResponse: Decodable {
	struct DataContainer: Decodable {
		let repository: Repository?
	}

	struct Repository: Decodable {
		let pullRequest: PullRequest?
	}

	struct PullRequest: Decodable {
		let reviewThreads: ReviewThreads?
	}

	struct ReviewThreads: Decodable {
		let nodes: [ReviewThread]?
	}

	struct ReviewThread: Decodable {
		let isResolved: Bool
	}

	let data: DataContainer?

	/// `nil` when the PR or its threads are missing from the response.
	var unresolvedCount: Int? {
		guard let nodes = data?.repository?.pullRequest?.reviewThreads?.nodes else {
			return nil
		}
		return nodes.count { !$0.isResolved }
	}
}
