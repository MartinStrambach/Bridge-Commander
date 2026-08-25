import Foundation

public nonisolated enum GitLabService {
	private static let graphQLURL = "https://gitlab.com/api/graphql"

	/// Fetches the branch's most recently created MR — state, head pipeline, and unresolved
	/// discussion count — in a single GraphQL request.
	///
	/// Returns `nil` only when the API confirmed no MR exists for the branch; any failure
	/// to get an answer (missing token, network, HTTP, decoding) throws instead, so
	/// callers can keep last-known state rather than treating the branch as MR-less.
	public static func fetchMergeRequest(
		projectPath: String,
		branch: String,
		token: String
	) async throws -> PullRequestDetails? {
		guard !token.isEmpty else {
			print("GitLabService: No token configured, skipping MR fetch")
			throw GitHostingError.missingToken
		}
		guard let url = URL(string: graphQLURL) else {
			throw GitHostingError.invalidURL
		}

		let query = """
		query($fullPath: ID!, $branch: String!) {
			project(fullPath: $fullPath) {
				mergeRequests(sourceBranches: [$branch], sort: CREATED_DESC, first: 1) {
					nodes {
						webUrl
						state
						draft
						resolvableDiscussionsCount
						resolvedDiscussionsCount
						headPipeline {
							status
							path
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

		request.httpBody = try JSONEncoder().encode(
			GitLabGraphQLRequest(
				query: query,
				variables: .init(fullPath: projectPath, branch: branch)
			)
		)

		print("GitLabService: Fetching MR for \(projectPath) on branch \(branch)")
		let (data, response) = try await URLSession.shared.data(for: request)

		guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
			let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
			throw GitHostingError.httpFailure(statusCode: statusCode)
		}

		let decoded = try JSONDecoder().decode(GitLabMergeRequestResponse.self, from: data)
		guard let mergeRequest = decoded.mergeRequest else {
			print("GitLabService: No MR found for \(projectPath) on branch \(branch)")
			return nil
		}

		return PullRequestDetails(
			url: mergeRequest.webUrl,
			state: mergeRequest.mappedState,
			provider: .gitlab,
			pipeline: mergeRequest.pipelineStatus,
			unresolvedDiscussionsCount: mergeRequest.unresolvedCount
		)
	}
}

private struct GitLabGraphQLRequest: Encodable {
	struct Variables: Encodable {
		let fullPath: String
		let branch: String
	}

	let query: String
	let variables: Variables
}

/// Internal (not private) so the response mapping is unit-testable from fixture JSON.
nonisolated struct GitLabMergeRequestResponse: Decodable {
	struct DataContainer: Decodable {
		let project: Project?
	}

	struct Project: Decodable {
		let mergeRequests: MergeRequests?
	}

	struct MergeRequests: Decodable {
		let nodes: [MergeRequest]?
	}

	struct MergeRequest: Decodable {
		let webUrl: String
		let state: String
		let draft: Bool?
		let resolvableDiscussionsCount: Int?
		let resolvedDiscussionsCount: Int?
		let headPipeline: HeadPipeline?

		var mappedState: PullRequestState {
			switch state.lowercased() {
			case "merged":
				return .merged
			case "closed":
				return .closed
			default:
				// "opened" and "locked"
				if draft == true {
					return .draft
				}
				return .ready
			}
		}

		/// Unresolved = resolvable − resolved, clamped at 0. `nil` when the counts are missing.
		var unresolvedCount: Int? {
			guard
				let resolvable = resolvableDiscussionsCount,
				let resolved = resolvedDiscussionsCount
			else {
				return nil
			}
			return max(0, resolvable - resolved)
		}

		var pipelineStatus: PipelineStatus? {
			guard
				let headPipeline,
				// GraphQL reports the same statuses as REST, as uppercase enum cases.
				let state = PipelineState(gitLabStatus: headPipeline.status.lowercased()),
				let path = headPipeline.path
			else {
				return nil
			}
			return PipelineStatus(state: state, url: "https://gitlab.com" + path)
		}
	}

	struct HeadPipeline: Decodable {
		let status: String
		let path: String?
	}

	let data: DataContainer?

	/// The branch's most recently created MR, or `nil` when none exists.
	var mergeRequest: MergeRequest? {
		data?.project?.mergeRequests?.nodes?.first
	}
}
