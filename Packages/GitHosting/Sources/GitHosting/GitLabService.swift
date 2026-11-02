import ActivityLog
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
						iid
						webUrl
						state
						draft
						resolvableDiscussionsCount
						resolvedDiscussionsCount
						approved
						approvalsRequired
						approvalsLeft
						groupedApprovalsRequired
						groupedApprovalsLeft
						detailedMergeStatus
						conflicts
						autoMergeEnabled
						autoMergeStrategy
						approvedBy {
							nodes { username name avatarUrl }
						}
						reviewers {
							nodes {
								username
								name
								avatarUrl
								mergeRequestInteraction { reviewState }
							}
						}
						headPipeline {
							status
							path
							mergeRequestEventType
						}
					}
				}
			}
		}
		"""

		print("GitLabService: Fetching MR for \(projectPath) on branch \(branch)")
		let data = try await post(
			GitLabGraphQLRequest(
				query: query,
				variables: .init(fullPath: projectPath, branch: branch)
			),
			to: url,
			token: token
		)

		let decoded = try JSONDecoder().decode(GitLabMergeRequestResponse.self, from: data)
		// A 200 with a null project means the token cannot see the project (missing
		// scope, no membership, or a fine-grained token's GraphQL gaps) — not that
		// the branch has no MR. Only a visible project with no nodes means that.
		guard decoded.data?.project != nil else {
			print("GitLabService: Token cannot access \(projectPath)")
			throw GitHostingError.unauthenticated
		}
		guard let mergeRequest = decoded.mergeRequest else {
			print("GitLabService: No MR found for \(projectPath) on branch \(branch)")
			return nil
		}

		var pipeline = mergeRequest.pipelineStatus
		var mergeTrain = mergeRequest.mergeTrainStatus
		if case .onTrain = mergeTrain, let iid = mergeRequest.iid,
		   let car = await fetchMergeTrainCar(projectPath: projectPath, iid: iid, token: token, url: url) {
			mergeTrain = .onTrain(position: car.position)
			// The car's pipeline is the one that decides the merge, whatever the MR
			// reports as its head pipeline.
			pipeline = car.pipelineStatus ?? pipeline
		}

		return PullRequestDetails(
			url: mergeRequest.webUrl,
			state: mergeRequest.mappedState,
			provider: .gitlab,
			pipeline: pipeline,
			unresolvedDiscussionsCount: mergeRequest.unresolvedCount,
			approvals: mergeRequest.approvalStatus,
			hasConflicts: mergeRequest.hasConflicts,
			mergeTrain: mergeTrain
		)
	}

	/// The MR's car on the merge train: its position and pipeline.
	///
	/// Best effort, in its own request: GitLab marks `mergeTrainCar` experimental, and
	/// were it changed or removed, asking for it in the main query would fail the whole
	/// MR fetch. Any failure returns `nil` and the row goes without the position.
	private static func fetchMergeTrainCar(
		projectPath: String,
		iid: String,
		token: String,
		url: URL
	) async -> GitLabMergeTrainCarResponse.Car? {
		let query = """
		query($fullPath: ID!, $iid: String!) {
			project(fullPath: $fullPath) {
				mergeRequest(iid: $iid) {
					mergeTrainCar {
						index
						pipeline {
							status
							path
							mergeRequestEventType
						}
					}
				}
			}
		}
		"""
		do {
			let data = try await post(
				GitLabMergeTrainCarRequest(query: query, variables: .init(fullPath: projectPath, iid: iid)),
				to: url,
				token: token
			)
			return try JSONDecoder().decode(GitLabMergeTrainCarResponse.self, from: data).car
		}
		catch {
			print("GitLabService: Could not fetch merge train car for \(projectPath)!\(iid): \(error)")
			return nil
		}
	}

	/// POSTs a GraphQL request body and returns the response data of a 200 answer.
	private static func post(_ body: some Encodable, to url: URL, token: String) async throws -> Data {
		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.setValue("application/json", forHTTPHeaderField: "Accept")
		request.httpBody = try JSONEncoder().encode(body)

		let (data, response) = try await URLSession.shared.loggedData(for: request)
		guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
			throw GitHostingError.httpFailure(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1)
		}
		return data
	}

	/// Verifies the token against the same GraphQL endpoint the MR fetch uses,
	/// returning the username it authenticates as.
	public static func verifyToken(_ token: String) async throws -> String {
		guard !token.isEmpty else {
			throw GitHostingError.missingToken
		}
		guard let url = URL(string: graphQLURL) else {
			throw GitHostingError.invalidURL
		}

		let data = try await post(
			BareGraphQLRequest(query: "{ currentUser { username } }"),
			to: url,
			token: token
		)

		let decoded = try JSONDecoder().decode(GitLabCurrentUserResponse.self, from: data)
		guard let username = decoded.username else {
			throw GitHostingError.unauthenticated
		}
		return username
	}
}

/// GitLab reports user avatars either as a full URL (Gravatar) or as an
/// instance-relative path (`/uploads/-/system/user/avatar/...`). Mirrors how
/// `headPipeline.path` is turned into a link.
/// Internal (not private) so it is unit-testable.
nonisolated enum GitLabAvatarURL {
	static func absolute(_ raw: String?) -> String? {
		guard let raw, !raw.isEmpty else {
			return nil
		}
		return raw.hasPrefix("/") ? "https://gitlab.com" + raw : raw
	}
}

/// Internal (not private) so the response mapping is unit-testable from fixture JSON.
nonisolated struct GitLabCurrentUserResponse: Decodable {
	struct DataContainer: Decodable {
		let currentUser: User?
	}

	struct User: Decodable {
		let username: String
	}

	let data: DataContainer?

	var username: String? {
		data?.currentUser?.username
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

private struct GitLabMergeTrainCarRequest: Encodable {
	struct Variables: Encodable {
		let fullPath: String
		let iid: String
	}

	let query: String
	let variables: Variables
}

/// Internal (not private) so the response mapping is unit-testable from fixture JSON.
nonisolated struct GitLabMergeTrainCarResponse: Decodable {
	struct DataContainer: Decodable {
		let project: Project?
	}

	struct Project: Decodable {
		let mergeRequest: MergeRequest?
	}

	struct MergeRequest: Decodable {
		let mergeTrainCar: Car?
	}

	struct Car: Decodable {
		/// Zero-based; `nil` when the car is not active on a train.
		let index: Int?
		let pipeline: GitLabMergeRequestResponse.HeadPipeline?

		/// Position counted from 1, as people say it.
		var position: Int? {
			index.map { $0 + 1 }
		}

		var pipelineStatus: PipelineStatus? {
			pipeline?.pipelineStatus
		}
	}

	let data: DataContainer?

	var car: Car? {
		data?.project?.mergeRequest?.mergeTrainCar
	}
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
		let iid: String?
		let webUrl: String
		let state: String
		let draft: Bool?
		let resolvableDiscussionsCount: Int?
		let resolvedDiscussionsCount: Int?
		let approved: Bool?
		let approvalsRequired: Int?
		let approvalsLeft: Int?
		let groupedApprovalsRequired: Int?
		let groupedApprovalsLeft: Int?
		let detailedMergeStatus: String?
		let conflicts: Bool?
		let autoMergeEnabled: Bool?
		let autoMergeStrategy: String?
		let approvedBy: UserConnection?
		let reviewers: ReviewerConnection?
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
			headPipeline?.pipelineStatus
		}

		/// Merge train state from the auto-merge strategy. The position is not here:
		/// it needs `mergeTrainCar`, fetched separately. Merged/closed MRs have none.
		var mergeTrainStatus: MergeTrainStatus? {
			guard mappedState.isOpen, autoMergeEnabled != false else {
				return nil
			}
			return switch autoMergeStrategy?.uppercased() {
			case "MERGE_TRAIN": .onTrain(position: nil)
			case "ADD_TO_MERGE_TRAIN_WHEN_CHECKS_PASS": .waitingToJoin
			default: nil
			}
		}

		/// Whether the MR cannot merge cleanly into its target branch.
		///
		/// `conflicts` is the direct flag; `detailedMergeStatus` is checked as well in case
		/// a response omits it. The status alone is not enough — it reports a single
		/// reason, so a higher-priority blocker can mask the conflict.
		var hasConflicts: Bool {
			conflicts == true || detailedMergeStatus?.uppercased() == "CONFLICT"
		}

		/// Reviewers who explicitly asked for changes.
		///
		/// Only the ones still listed as reviewers can be named — GitLab keeps the
		/// blocking review after someone is removed from `reviewers`, so this can come
		/// back empty on an MR that is genuinely blocked. `isBlockedByRequestedChanges`
		/// is what decides the verdict; this only supplies faces for it.
		var changesRequestedReviewers: [Reviewer] {
			(reviewers?.nodes ?? [])
				.filter { $0.mergeRequestInteraction?.reviewState?.uppercased() == "REQUESTED_CHANGES" }
				.map(\.reviewer)
		}

		/// Whether a requested change is holding the MR up.
		///
		/// `detailedMergeStatus` is the authoritative signal and survives the reviewer
		/// being unassigned, but it reports a single reason with a precedence order, so
		/// a higher-priority blocker (a conflict, say) can mask it. Checking the
		/// reviewers as well covers that.
		var isBlockedByRequestedChanges: Bool {
			detailedMergeStatus?.uppercased() == "REQUESTED_CHANGES" || !changesRequestedReviewers.isEmpty
		}

		var approvalStatus: ApprovalStatus {
			let changesRequestedBy = changesRequestedReviewers
			let approvedBy = (self.approvedBy?.nodes ?? []).map(\.reviewer)

			let decision: ApprovalDecision =
				if isBlockedByRequestedChanges {
					.changesRequested
				}
				else if approved == true {
					.approved
				}
				else {
					.reviewRequired
				}

			// Prefer the grouped counts: they collapse rules that share a section and
			// approvers, so a reviewer who covers several categories at once counts
			// once rather than leaving the MR reading as "2 of 8" when it is fully
			// approved. The ungrouped pair is the fallback for responses that omit them.
			let required = groupedApprovalsRequired ?? approvalsRequired
			let left = groupedApprovalsLeft ?? approvalsLeft

			return ApprovalStatus(
				decision: decision,
				approvedBy: approvedBy,
				changesRequestedBy: changesRequestedBy,
				// Passed through as reported, 0 included: a project with no approval rule
				// requires no sign-off, and the row hides its approval slot on that. Only
				// an absent field stays nil, which means "count unknown".
				approvalsRequired: required,
				approvalsLeft: left
			)
		}
	}

	struct UserConnection: Decodable {
		let nodes: [User]?
	}

	struct ReviewerConnection: Decodable {
		let nodes: [ReviewerNode]?
	}

	struct User: Decodable {
		let username: String
		let name: String?
		let avatarUrl: String?

		var reviewer: Reviewer {
			Reviewer(
				username: username,
				displayName: name ?? username,
				avatarURL: GitLabAvatarURL.absolute(avatarUrl)
			)
		}
	}

	struct ReviewerNode: Decodable {
		let username: String
		let name: String?
		let avatarUrl: String?
		let mergeRequestInteraction: MergeRequestInteraction?

		var reviewer: Reviewer {
			Reviewer(
				username: username,
				displayName: name ?? username,
				avatarURL: GitLabAvatarURL.absolute(avatarUrl)
			)
		}
	}

	struct MergeRequestInteraction: Decodable {
		let reviewState: String?
	}

	struct HeadPipeline: Decodable {
		let status: String
		let path: String?
		/// `DETACHED`, `MERGED_RESULT` or `MERGE_TRAIN`; absent for branch pipelines.
		let mergeRequestEventType: String?

		var pipelineStatus: PipelineStatus? {
			guard
				// GraphQL reports the same statuses as REST, as uppercase enum cases.
				let state = PipelineState(gitLabStatus: status.lowercased()),
				let path
			else {
				return nil
			}
			return PipelineStatus(
				state: state,
				url: "https://gitlab.com" + path,
				isMergeTrain: mergeRequestEventType?.uppercased() == "MERGE_TRAIN"
			)
		}
	}

	let data: DataContainer?

	/// The branch's most recently created MR, or `nil` when none exists.
	var mergeRequest: MergeRequest? {
		data?.project?.mergeRequests?.nodes?.first
	}
}
