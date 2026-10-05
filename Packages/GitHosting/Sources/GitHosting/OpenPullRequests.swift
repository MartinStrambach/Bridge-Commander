import Foundation

/// An open PR/MR that a worktree can be checked out for.
public nonisolated struct OpenPullRequest: Equatable, Sendable, Identifiable {
	/// GitHub's PR number / GitLab's project-scoped `iid`.
	public let number: Int
	public let title: String
	/// The head branch, on `origin` — PRs from forks are left out, their branch is elsewhere.
	public let sourceBranch: String
	public let author: String?
	public let url: String
	public let isDraft: Bool
	public let provider: PullRequestProvider

	public var id: Int { number }

	/// `#12` on GitHub, `!12` on GitLab — what each provider's own UI calls it.
	public var reference: String {
		(provider == .gitlab ? "!" : "#") + String(number)
	}

	public init(
		number: Int,
		title: String,
		sourceBranch: String,
		author: String?,
		url: String,
		isDraft: Bool,
		provider: PullRequestProvider
	) {
		self.number = number
		self.title = title
		self.sourceBranch = sourceBranch
		self.author = author
		self.url = url
		self.isDraft = isDraft
		self.provider = provider
	}
}

/// How many open PRs/MRs one listing returns, most recently updated first.
nonisolated let openPullRequestLimit = 50

// MARK: - GitHub

public nonisolated extension GitHubService {
	/// Lists the repository's open PRs whose head branch lives in the repository itself.
	static func fetchOpenPullRequests(owner: String, repo: String, token: String) async throws -> [OpenPullRequest] {
		let query = """
		query($owner: String!, $name: String!, $first: Int!) {
			repository(owner: $owner, name: $name) {
				pullRequests(states: OPEN, first: $first, orderBy: {field: UPDATED_AT, direction: DESC}) {
					nodes {
						number
						title
						url
						isDraft
						headRefName
						isCrossRepository
						author { login }
					}
				}
			}
		}
		"""
		let data = try await postGraphQL(
			url: "https://api.github.com/graphql",
			token: token,
			body: OpenPullRequestsRequest(
				query: query,
				variables: ["owner": .string(owner), "name": .string(repo), "first": .int(openPullRequestLimit)]
			)
		)
		let decoded = try JSONDecoder().decode(GitHubOpenPullRequestsResponse.self, from: data)
		guard let pullRequests = decoded.pullRequests else {
			throw GitHostingError.unauthenticated
		}
		return pullRequests
	}
}

/// Internal (not private) so the response mapping is unit-testable from fixture JSON.
nonisolated struct GitHubOpenPullRequestsResponse: Decodable {
	struct DataContainer: Decodable {
		let repository: Repository?
	}

	struct Repository: Decodable {
		let pullRequests: Connection?
	}

	struct Connection: Decodable {
		let nodes: [Node]?
	}

	struct Node: Decodable {
		let number: Int
		let title: String
		let url: String
		let isDraft: Bool?
		let headRefName: String
		let isCrossRepository: Bool?
		let author: Author?
	}

	struct Author: Decodable {
		let login: String
	}

	let data: DataContainer?

	/// Nil when the repository is not visible to the token — a 200 with a null repository is an
	/// access problem, not an empty list.
	var pullRequests: [OpenPullRequest]? {
		guard let repository = data?.repository else {
			return nil
		}
		return (repository.pullRequests?.nodes ?? [])
			.filter { $0.isCrossRepository != true }
			.map {
				OpenPullRequest(
					number: $0.number,
					title: $0.title,
					sourceBranch: $0.headRefName,
					author: $0.author?.login,
					url: $0.url,
					isDraft: $0.isDraft == true,
					provider: .github
				)
			}
	}
}

// MARK: - GitLab

public nonisolated extension GitLabService {
	/// Lists the project's open MRs whose source branch lives in the project itself.
	static func fetchOpenMergeRequests(projectPath: String, token: String) async throws -> [OpenPullRequest] {
		let query = """
		query($fullPath: ID!, $first: Int!) {
			project(fullPath: $fullPath) {
				mergeRequests(state: opened, sort: UPDATED_DESC, first: $first) {
					nodes {
						iid
						title
						webUrl
						draft
						sourceBranch
						sourceProjectId
						targetProjectId
						author { username }
					}
				}
			}
		}
		"""
		let data = try await postGraphQL(
			url: "https://gitlab.com/api/graphql",
			token: token,
			body: OpenPullRequestsRequest(
				query: query,
				variables: ["fullPath": .string(projectPath), "first": .int(openPullRequestLimit)]
			)
		)
		let decoded = try JSONDecoder().decode(GitLabOpenMergeRequestsResponse.self, from: data)
		guard let mergeRequests = decoded.mergeRequests else {
			throw GitHostingError.unauthenticated
		}
		return mergeRequests
	}
}

/// Internal (not private) so the response mapping is unit-testable from fixture JSON.
nonisolated struct GitLabOpenMergeRequestsResponse: Decodable {
	struct DataContainer: Decodable {
		let project: Project?
	}

	struct Project: Decodable {
		let mergeRequests: Connection?
	}

	struct Connection: Decodable {
		let nodes: [Node]?
	}

	struct Node: Decodable {
		/// GitLab's GraphQL reports `iid` as a string.
		let iid: String
		let title: String
		let webUrl: String
		let draft: Bool?
		let sourceBranch: String
		let sourceProjectId: Int?
		let targetProjectId: Int?
		let author: Author?
	}

	struct Author: Decodable {
		let username: String
	}

	let data: DataContainer?

	/// Nil when the project is not visible to the token, as for the single-MR fetch.
	var mergeRequests: [OpenPullRequest]? {
		guard let project = data?.project else {
			return nil
		}
		return (project.mergeRequests?.nodes ?? []).compactMap { node in
			// A fork's MR has its source branch in the fork, which `origin` does not have.
			if let source = node.sourceProjectId, let target = node.targetProjectId, source != target {
				return nil
			}
			guard let number = Int(node.iid) else {
				return nil
			}
			return OpenPullRequest(
				number: number,
				title: node.title,
				sourceBranch: node.sourceBranch,
				author: node.author?.username,
				url: node.webUrl,
				isDraft: node.draft == true,
				provider: .gitlab
			)
		}
	}
}

// MARK: - Shared request plumbing

private nonisolated enum GraphQLVariable: Encodable {
	case string(String)
	case int(Int)

	func encode(to encoder: any Encoder) throws {
		var container = encoder.singleValueContainer()
		switch self {
		case let .string(value): try container.encode(value)
		case let .int(value): try container.encode(value)
		}
	}
}

private nonisolated struct OpenPullRequestsRequest: Encodable {
	let query: String
	let variables: [String: GraphQLVariable]
}

/// POSTs a GraphQL body with the token and returns the payload of a 200. Same failure contract as
/// the single PR/MR fetches: no token, a bad URL and a non-200 all throw.
private nonisolated func postGraphQL(
	url urlString: String,
	token: String,
	body: some Encodable
) async throws -> Data {
	guard !token.isEmpty else {
		throw GitHostingError.missingToken
	}
	guard let url = URL(string: urlString) else {
		throw GitHostingError.invalidURL
	}

	var request = URLRequest(url: url)
	request.httpMethod = "POST"
	request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
	request.setValue("application/json", forHTTPHeaderField: "Content-Type")
	request.setValue("application/json", forHTTPHeaderField: "Accept")
	request.httpBody = try JSONEncoder().encode(body)

	let (data, response) = try await URLSession.shared.data(for: request)
	guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
		throw GitHostingError.httpFailure(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1)
	}
	return data
}
