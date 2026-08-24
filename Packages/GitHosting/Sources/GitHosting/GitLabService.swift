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

			let pipeline = await fetchHeadPipeline(
				encodedProject: encodedProject,
				iid: first.iid,
				token: token
			)

			return PullRequestDetails(
				url: first.web_url,
				state: first.mappedState,
				provider: .gitlab,
				number: first.iid,
				pipeline: pipeline
			)
		}
		catch {
			print("GitLabService: Error: \(error)")
			return nil
		}
	}

	/// Best-effort fetch of the MR's `head_pipeline`. Returns `nil` on any failure so the
	/// merge request is still reported even when the pipeline call fails.
	private static func fetchHeadPipeline(
		encodedProject: String,
		iid: Int,
		token: String
	) async -> PipelineStatus? {
		let urlString = "\(baseURL)/projects/\(encodedProject)/merge_requests/\(iid)"
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
				print("GitLabService: Pipeline fetch failed with status code \(statusCode)")
				return nil
			}

			let detail = try JSONDecoder().decode(GitLabMergeRequestDetail.self, from: data)
			guard
				let head = detail.head_pipeline,
				let state = PipelineState(gitLabStatus: head.status)
			else {
				return nil
			}
			return PipelineStatus(state: state, url: head.web_url)
		}
		catch {
			print("GitLabService: Pipeline fetch error: \(error)")
			return nil
		}
	}

	/// Best-effort fetch of the MR's unresolved discussion count. The REST API only exposes
	/// the paginated discussions list, so this uses the GraphQL counts instead (one request,
	/// exact numbers). Returns `nil` on any failure.
	public static func fetchUnresolvedDiscussionsCount(
		projectPath: String,
		iid: Int,
		token: String
	) async -> Int? {
		guard !token.isEmpty, let url = URL(string: "https://gitlab.com/api/graphql") else {
			return nil
		}

		let query = """
		query($fullPath: ID!, $iid: String!) {
			project(fullPath: $fullPath) {
				mergeRequest(iid: $iid) {
					resolvableDiscussionsCount
					resolvedDiscussionsCount
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
				GitLabGraphQLRequest(
					query: query,
					variables: .init(fullPath: projectPath, iid: String(iid))
				)
			)

			print("GitLabService: Fetching discussion counts for \(projectPath)!\(iid)")
			let (data, response) = try await URLSession.shared.data(for: request)

			guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
				let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
				print("GitLabService: Discussion counts fetch failed with status code \(statusCode)")
				return nil
			}

			return try JSONDecoder().decode(GitLabDiscussionCountsResponse.self, from: data).unresolvedCount
		}
		catch {
			print("GitLabService: Discussion counts fetch error: \(error)")
			return nil
		}
	}
}

private struct GitLabMergeRequest: Decodable {
	let iid: Int
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

private struct GitLabMergeRequestDetail: Decodable {
	let head_pipeline: GitLabHeadPipeline?
}

private struct GitLabGraphQLRequest: Encodable {
	struct Variables: Encodable {
		let fullPath: String
		let iid: String
	}

	let query: String
	let variables: Variables
}

/// Internal (not private) so the count derivation is unit-testable from fixture JSON.
nonisolated struct GitLabDiscussionCountsResponse: Decodable {
	struct DataContainer: Decodable {
		let project: Project?
	}

	struct Project: Decodable {
		let mergeRequest: MergeRequest?
	}

	struct MergeRequest: Decodable {
		let resolvableDiscussionsCount: Int?
		let resolvedDiscussionsCount: Int?
	}

	let data: DataContainer?

	/// Unresolved = resolvable − resolved, clamped at 0. `nil` when the MR or counts are missing.
	var unresolvedCount: Int? {
		guard
			let mergeRequest = data?.project?.mergeRequest,
			let resolvable = mergeRequest.resolvableDiscussionsCount,
			let resolved = mergeRequest.resolvedDiscussionsCount
		else {
			return nil
		}
		return max(0, resolvable - resolved)
	}
}

private struct GitLabHeadPipeline: Decodable {
	let status: String
	let web_url: String
}
