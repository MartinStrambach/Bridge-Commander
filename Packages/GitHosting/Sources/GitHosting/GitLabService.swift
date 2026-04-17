import Foundation

public nonisolated enum GitLabService {
	private static let baseURL = "https://gitlab.com/api/v4"

	public static func fetchMergeRequest(
		projectPath: String,
		branch: String,
		token: String
	) async -> PullRequestDetails? {
		guard !token.isEmpty else {
			print("GitLabService: No token configured, skipping MR fetch")
			return nil
		}
		guard
			let encodedProject = projectPath
				.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed.subtracting(.init(charactersIn: "/"))),
				let encodedBranch = branch.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
		else {
			return nil
		}

		let urlString =
			"\(baseURL)/projects/\(encodedProject)/merge_requests?source_branch=\(encodedBranch)&order_by=created_at&sort=desc&per_page=1"
		guard let url = URL(string: urlString) else {
			return nil
		}

		var request = URLRequest(url: url)
		request.httpMethod = "GET"
		request.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")
		request.setValue("application/json", forHTTPHeaderField: "Accept")

		do {
			print("GitLabService: Fetching \(urlString)")
			let (data, response) = try await URLSession.shared.data(for: request)

			guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
				let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
				print("GitLabService: Failed with status code \(statusCode)")
				return nil
			}

			let mrs = try JSONDecoder().decode([GitLabMergeRequest].self, from: data)
			guard let first = mrs.first else {
				print("GitLabService: No MR found for \(projectPath) on branch \(branch)")
				return nil
			}

			return PullRequestDetails(
				url: first.web_url,
				state: first.mappedState,
				provider: .gitlab
			)
		}
		catch {
			print("GitLabService: Error: \(error)")
			return nil
		}
	}
}

private struct GitLabMergeRequest: Decodable {
	let web_url: String
	let state: String
	let draft: Bool?
	let work_in_progress: Bool?

	var mappedState: PullRequestState {
		switch state {
		case "merged":
			return .merged
		case "closed":
			return .closed
		default:
			if draft == true || work_in_progress == true {
				return .draft
			}
			return .ready
		}
	}
}
