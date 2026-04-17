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
				provider: .github
			)
		}
		catch {
			print("GitHubService: Error: \(error)")
			return nil
		}
	}
}

private struct GitHubPullRequest: Decodable {
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
