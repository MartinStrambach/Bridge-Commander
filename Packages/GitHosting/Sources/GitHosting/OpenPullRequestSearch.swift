import Foundation

/// What the create-worktree dialog's filter text asks for. It is matched locally against the
/// listed PRs/MRs, which are only the most recently updated ones, and searched for on the host
/// to find the rest.
public nonisolated struct OpenPullRequestQuery: Equatable, Sendable {
	/// The trimmed filter text.
	public let filter: String
	/// Searched for in titles and descriptions. Nil when the text only names a PR/MR (`!12`,
	/// `#12`, a link to it), whose words would match nothing.
	public let searchText: String?
	/// The PR/MR the text names: its number, `!12` / `#12`, or a link to it.
	public let number: Int?
	/// The text as an exact source branch name: the hosts' text search does not look at branches.
	public let branch: String?

	/// Nil for blank text, which asks for nothing.
	public init?(_ text: String) {
		let filter = text.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !filter.isEmpty else {
			return nil
		}
		self.filter = filter
		if let match = filter.wholeMatch(of: /([!#])?(\d{1,9})/) {
			self.number = Int(match.output.2)
			// Plain digits may also be in a title ("2026"); `!12` and `#12` only name a PR/MR.
			self.searchText = match.output.1 == nil ? filter : nil
			self.branch = nil
		}
		else if let match = filter.firstMatch(of: /\/(?:merge_requests|pull)\/(\d{1,9})(?:[\/?#]|$)/) {
			self.number = Int(match.output.1)
			self.searchText = nil
			self.branch = nil
		}
		else {
			self.number = nil
			self.searchText = filter
			self.branch = filter.contains(where: \.isWhitespace) ? nil : filter
		}
	}

	/// Whether a listed PR/MR matches without asking the host: its title, branch, reference
	/// (`!12` / `#12`, so also part of the number) or author contains the text, or it is the PR/MR
	/// the text names.
	public func matches(_ pullRequest: OpenPullRequest) -> Bool {
		pullRequest.number == number
			|| pullRequest.title.localizedCaseInsensitiveContains(filter)
			|| pullRequest.sourceBranch.localizedCaseInsensitiveContains(filter)
			|| pullRequest.reference.contains(filter)
			|| (pullRequest.author?.localizedCaseInsensitiveContains(filter) ?? false)
	}
}

/// The PRs/MRs of several lookups, first occurrence kept, in the order given.
nonisolated func uniqueByNumber(_ lists: [OpenPullRequest]...) -> [OpenPullRequest] {
	var seen = Set<Int>()
	return lists.joined().filter { seen.insert($0.number).inserted }
}

// MARK: - GitHub

public nonisolated extension GitHubService {
	/// Searches the repository's open PRs, those from forks included: the PR the query names,
	/// the one whose head branch it is, and those whose title or description matches it, in
	/// that order. One request; a lookup the query does not need is skipped by `@include`.
	static func searchOpenPullRequests(
		owner: String,
		repo: String,
		query: OpenPullRequestQuery,
		token: String
	) async throws -> [OpenPullRequest] {
		let graphQL = """
		query(
			$owner: String!, $name: String!, $first: Int!,
			$number: Int!, $search: String!, $branchSearch: String!,
			$withNumber: Boolean!, $withSearch: Boolean!, $withBranch: Boolean!
		) {
			repository(owner: $owner, name: $name) {
				id
				byNumber: pullRequest(number: $number) @include(if: $withNumber) { ...OpenPullRequest state }
			}
			byBranch: search(query: $branchSearch, type: ISSUE, first: $first) @include(if: $withBranch) {
				nodes { ...OpenPullRequest }
			}
			bySearch: search(query: $search, type: ISSUE, first: $first) @include(if: $withSearch) {
				nodes { ...OpenPullRequest }
			}
		}
		fragment OpenPullRequest on PullRequest {
			number
			title
			url
			isDraft
			headRefName
			isCrossRepository
			headRepositoryOwner { login }
			viewerDidAuthor
			author { login }
			baseRepository { nameWithOwner }
		}
		"""
		let scope = "repo:\(owner)/\(repo) is:pr is:open"
		let data = try await postGraphQL(
			url: "https://api.github.com/graphql",
			token: token,
			body: OpenPullRequestsRequest(
				query: graphQL,
				variables: [
					"owner": .string(owner),
					"name": .string(repo),
					"first": .int(openPullRequestLimit),
					// Non-null in the schema, so a skipped lookup still gets a placeholder.
					"number": .int(query.number ?? 0),
					"search": .string("\(scope) \(query.searchText ?? "")"),
					"branchSearch": .string("\(scope) head:\(query.branch ?? "")"),
					"withNumber": .bool(query.number != nil),
					"withSearch": .bool(query.searchText != nil),
					"withBranch": .bool(query.branch != nil),
				]
			)
		)
		let decoded = try JSONDecoder().decode(GitHubPullRequestSearchResponse.self, from: data)
		guard let pullRequests = decoded.pullRequests(in: "\(owner)/\(repo)") else {
			throw GitHostingError.unauthenticated
		}
		return pullRequests
	}
}

/// Internal (not private) so the response mapping is unit-testable from fixture JSON.
nonisolated struct GitHubPullRequestSearchResponse: Decodable {
	typealias Node = GitHubOpenPullRequestsResponse.Node

	struct DataContainer: Decodable {
		let repository: Repository?
		let byBranch: SearchConnection?
		let bySearch: SearchConnection?
	}

	struct Repository: Decodable {
		/// Null for a number that is an issue, or no PR at all, which GitHub also reports as an
		/// error beside the data.
		let byNumber: Node?
	}

	struct SearchConnection: Decodable {
		let nodes: [SearchNode]?
	}

	/// A search hit. `is:pr` keeps issues out, but an issue would come back as `{}`, which must
	/// not fail the whole answer; a PR of an unexpected shape still does.
	struct SearchNode: Decodable {
		let pullRequest: Node?

		private struct AnyKey: CodingKey {
			let stringValue: String
			var intValue: Int? { nil }
			init(stringValue: String) { self.stringValue = stringValue }
			init?(intValue: Int) { nil }
		}

		init(from decoder: any Decoder) throws {
			let isEmpty = try decoder.container(keyedBy: AnyKey.self).allKeys.isEmpty
			self.pullRequest = isEmpty ? nil : try Node(from: decoder)
		}
	}

	struct BaseRepository: Decodable {
		let nameWithOwner: String
	}

	let data: DataContainer?

	/// Nil when the repository is not visible to the token, as for the listing. `nameWithOwner`
	/// is the searched repository: GitHub ORs `repo:` qualifiers, so a `repo:` in the typed text
	/// brings in other repositories' PRs, whose number or branch would check out the wrong code.
	func pullRequests(in nameWithOwner: String) -> [OpenPullRequest]? {
		guard let data, let repository = data.repository else {
			return nil
		}
		// A PR found by number may be closed or merged; the search hits are open by `is:open`.
		let byNumber = [repository.byNumber].compactMap { $0?.state == "OPEN" ? $0 : nil }
		func ownHits(_ connection: SearchConnection?) -> [Node] {
			(connection?.nodes ?? []).compactMap(\.pullRequest).filter {
				$0.baseRepository?.nameWithOwner.caseInsensitiveCompare(nameWithOwner) == .orderedSame
			}
		}
		let byBranch = ownHits(data.byBranch)
		let bySearch = ownHits(data.bySearch)
		return uniqueByNumber(
			byNumber.map(\.openPullRequest),
			byBranch.map(\.openPullRequest),
			bySearch.map(\.openPullRequest)
		)
	}
}

// MARK: - GitLab

public nonisolated extension GitLabService {
	/// Searches the project's open MRs, those from forks included: the MR the query names, those
	/// from the branch it names, and those whose title or description matches it, in that order.
	/// One request; a lookup the query does not need is skipped by `@include`.
	static func searchOpenMergeRequests(
		projectPath: String,
		query: OpenPullRequestQuery,
		token: String
	) async throws -> [OpenPullRequest] {
		let graphQL = """
		query(
			$fullPath: ID!, $first: Int!, $iids: [String!], $branches: [String!], $search: String,
			$withNumber: Boolean!, $withBranch: Boolean!, $withSearch: Boolean!
		) {
			currentUser { username }
			project(fullPath: $fullPath) {
				id
				byNumber: mergeRequests(state: opened, iids: $iids) @include(if: $withNumber) {
					...OpenMergeRequests
				}
				byBranch: mergeRequests(state: opened, sourceBranches: $branches) @include(if: $withBranch) {
					...OpenMergeRequests
				}
				bySearch: mergeRequests(state: opened, sort: UPDATED_DESC, first: $first, search: $search)
					@include(if: $withSearch) {
					...OpenMergeRequests
				}
			}
		}
		fragment OpenMergeRequests on MergeRequestConnection {
			nodes {
				iid
				title
				webUrl
				draft
				sourceBranch
				sourceProjectId
				targetProjectId
				sourceProject { fullPath }
				author { username }
			}
		}
		"""
		var variables: [String: GraphQLVariable] = [
			"fullPath": .string(projectPath),
			"first": .int(openPullRequestLimit),
			"withNumber": .bool(query.number != nil),
			"withBranch": .bool(query.branch != nil),
			"withSearch": .bool(query.searchText != nil),
		]
		// Nullable in the schema, so a skipped lookup's variable is simply left out.
		if let number = query.number {
			variables["iids"] = .strings([String(number)])
		}
		if let branch = query.branch {
			variables["branches"] = .strings([branch])
		}
		if let searchText = query.searchText {
			variables["search"] = .string(searchText)
		}
		let data = try await postGraphQL(
			url: "https://gitlab.com/api/graphql",
			token: token,
			body: OpenPullRequestsRequest(query: graphQL, variables: variables)
		)
		let decoded = try JSONDecoder().decode(GitLabMergeRequestSearchResponse.self, from: data)
		guard let mergeRequests = decoded.mergeRequests else {
			throw GitHostingError.unauthenticated
		}
		return mergeRequests
	}
}

/// Internal (not private) so the response mapping is unit-testable from fixture JSON.
nonisolated struct GitLabMergeRequestSearchResponse: Decodable {
	typealias Connection = GitLabOpenMergeRequestsResponse.Connection
	typealias Author = GitLabOpenMergeRequestsResponse.Author

	struct DataContainer: Decodable {
		let currentUser: Author?
		let project: Project?
	}

	struct Project: Decodable {
		let byNumber: Connection?
		let byBranch: Connection?
		let bySearch: Connection?
	}

	let data: DataContainer?

	/// Nil when the project is not visible to the token, as for the listing.
	var mergeRequests: [OpenPullRequest]? {
		guard let project = data?.project else {
			return nil
		}
		let viewer = data?.currentUser?.username
		func mapped(_ connection: Connection?) -> [OpenPullRequest] {
			(connection?.nodes ?? []).compactMap { $0.openPullRequest(viewer: viewer) }
		}
		return uniqueByNumber(mapped(project.byNumber), mapped(project.byBranch), mapped(project.bySearch))
	}
}
