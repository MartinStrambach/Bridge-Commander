import Foundation
import Testing
@testable import GitHosting

@Suite("GitLab MR GraphQL response")
struct GitLabMergeRequestResponseTests {
	private func decode(_ json: String) throws -> GitLabMergeRequestResponse {
		try JSONDecoder().decode(GitLabMergeRequestResponse.self, from: Data(json.utf8))
	}

	private func node(_ fields: String) -> String {
		#"{"data": {"project": {"mergeRequests": {"nodes": [{"webUrl": "https://gitlab.com/g/p/-/merge_requests/7", \#(fields)}]}}}}"#
	}

	@Test("parses a full merge request")
	func fullMergeRequest() throws {
		let json = node("""
		"state": "opened",
		"draft": false,
		"resolvableDiscussionsCount": 5,
		"resolvedDiscussionsCount": 3,
		"headPipeline": {"status": "SUCCESS", "path": "/g/p/-/pipelines/42"}
		""")
		let mergeRequest = try #require(decode(json).mergeRequest)
		#expect(mergeRequest.webUrl == "https://gitlab.com/g/p/-/merge_requests/7")
		#expect(mergeRequest.mappedState == .ready)
		#expect(mergeRequest.unresolvedCount == 2)
		#expect(mergeRequest.pipelineStatus == PipelineStatus(
			state: .success,
			url: "https://gitlab.com/g/p/-/pipelines/42"
		))
	}

	@Test("maps MR states, treating locked as open")
	func stateMapping() throws {
		#expect(try decode(node(#""state": "merged""#)).mergeRequest?.mappedState == .merged)
		#expect(try decode(node(#""state": "closed""#)).mergeRequest?.mappedState == .closed)
		#expect(try decode(node(#""state": "locked""#)).mergeRequest?.mappedState == .ready)
		#expect(try decode(node(#""state": "opened", "draft": true"#)).mergeRequest?.mappedState == .draft)
	}

	@Test("clamps resolved exceeding resolvable to zero")
	func clampsNegativeCount() throws {
		let json = node(#""state": "opened", "resolvableDiscussionsCount": 1, "resolvedDiscussionsCount": 2"#)
		#expect(try decode(json).mergeRequest?.unresolvedCount == 0)
	}

	@Test("missing counts report unknown")
	func missingCounts() throws {
		#expect(try decode(node(#""state": "opened""#)).mergeRequest?.unresolvedCount == nil)
	}

	@Test("maps uppercase multi-word pipeline status")
	func pipelineStatusMapping() throws {
		let json = node(
			#""state": "opened", "headPipeline": {"status": "WAITING_FOR_RESOURCE", "path": "/g/p/-/pipelines/1"}"#
		)
		#expect(try decode(json).mergeRequest?.pipelineStatus?.state == .waitingForResource)
	}

	@Test("missing, unknown-status, or pathless pipeline reports none")
	func missingPipeline() throws {
		#expect(try decode(node(#""state": "opened""#)).mergeRequest?.pipelineStatus == nil)
		#expect(
			try decode(node(#""state": "opened", "headPipeline": {"status": "BOGUS", "path": "/p"}"#))
				.mergeRequest?.pipelineStatus == nil
		)
		#expect(
			try decode(node(#""state": "opened", "headPipeline": {"status": "SUCCESS"}"#))
				.mergeRequest?.pipelineStatus == nil
		)
	}

	@Test("missing MR or project reports none")
	func missingMergeRequest() throws {
		#expect(try decode(#"{"data": {"project": {"mergeRequests": {"nodes": []}}}}"#).mergeRequest == nil)
		#expect(try decode(#"{"data": {"project": null}}"#).mergeRequest == nil)
		#expect(try decode(#"{"data": null}"#).mergeRequest == nil)
	}

	// MARK: - Approvals

	@Test("a satisfied MR reports approved with its approvers")
	func approved() throws {
		let json = node("""
		"state": "opened",
		"approved": true,
		"approvalsRequired": 2,
		"approvedBy": {"nodes": [
			{"username": "aberg", "name": "Astrid Berg", "avatarUrl": "/uploads/-/system/user/avatar/1/a.png"},
			{"username": "cdupont", "name": "Camille Dupont", "avatarUrl": "https://secure.gravatar.com/avatar/c"}
		]}
		""")
		let approvals = try #require(decode(json).mergeRequest?.approvalStatus)
		#expect(approvals.decision == .approved)
		#expect(approvals.approvalsRequired == 2)
		#expect(approvals.approvedBy.map(\.username) == ["aberg", "cdupont"])
		#expect(approvals.approvedBy[0].displayName == "Astrid Berg")
		// Instance-relative avatars are made absolute, Gravatar URLs are left alone.
		#expect(approvals.approvedBy[0].avatarURL == "https://gitlab.com/uploads/-/system/user/avatar/1/a.png")
		#expect(approvals.approvedBy[1].avatarURL == "https://secure.gravatar.com/avatar/c")
	}

	@Test("a blocking reviewer outranks a satisfied approval rule")
	func changesRequestedOutranksApproved() throws {
		let json = node("""
		"state": "opened",
		"approved": true,
		"approvedBy": {"nodes": [{"username": "aberg", "name": "Astrid Berg", "avatarUrl": null}]},
		"reviewers": {"nodes": [
			{"username": "rmehta", "name": "Rohan Mehta", "avatarUrl": null,
			 "mergeRequestInteraction": {"reviewState": "REQUESTED_CHANGES"}}
		]}
		""")
		let approvals = try #require(decode(json).mergeRequest?.approvalStatus)
		#expect(approvals.decision == .changesRequested)
		#expect(approvals.changesRequestedBy.map(\.username) == ["rmehta"])
		// The approval is still reported, it just does not drive the decision.
		#expect(approvals.approvedBy.map(\.username) == ["aberg"])
	}

	@Test("detailedMergeStatus reports requested changes when no reviewer is listed")
	func changesRequestedWithoutReviewers() throws {
		// Taken from a real blocked MR: GitLab keeps the blocking review after the
		// reviewer is unassigned, so `reviewers` comes back empty while the merge
		// status still says REQUESTED_CHANGES. Scanning reviewers alone read this
		// as merely awaiting review.
		let json = node("""
		"state": "opened",
		"draft": false,
		"approved": false,
		"approvalsRequired": 2,
		"approvalsLeft": 2,
		"groupedApprovalsRequired": 2,
		"groupedApprovalsLeft": 2,
		"detailedMergeStatus": "REQUESTED_CHANGES",
		"approvedBy": {"nodes": []},
		"reviewers": {"nodes": []}
		""")
		let approvals = try #require(decode(json).mergeRequest?.approvalStatus)
		#expect(approvals.decision == .changesRequested)
		// Nobody can be named, which is fine — the verdict does not depend on it.
		#expect(approvals.changesRequestedBy.isEmpty)
	}

	@Test("a requested change outranks a merge status that reports another blocker")
	func reviewerChangesRequestedSurvivesOtherMergeStatus() throws {
		// detailedMergeStatus reports one reason by precedence, so a conflict can
		// mask the requested change; the reviewer scan is what catches it.
		let json = node("""
		"state": "opened",
		"approved": false,
		"detailedMergeStatus": "CONFLICT",
		"reviewers": {"nodes": [
			{"username": "rmehta", "name": "Rohan Mehta", "avatarUrl": null,
			 "mergeRequestInteraction": {"reviewState": "REQUESTED_CHANGES"}}
		]}
		""")
		let approvals = try #require(decode(json).mergeRequest?.approvalStatus)
		#expect(approvals.decision == .changesRequested)
		#expect(approvals.changesRequestedBy.map(\.username) == ["rmehta"])
	}

	@Test("an unblocked merge status leaves the verdict to the approvals")
	func mergeableStatusDoesNotBlock() throws {
		let json = node("""
		"state": "opened",
		"approved": true,
		"detailedMergeStatus": "MERGEABLE",
		"approvedBy": {"nodes": [{"username": "aberg", "name": "Astrid Berg", "avatarUrl": null}]}
		""")
		#expect(try decode(json).mergeRequest?.approvalStatus.decision == .approved)
	}

	@Test("an unapproved MR awaits review")
	func reviewRequired() throws {
		let json = node("""
		"state": "opened",
		"approved": false,
		"reviewers": {"nodes": [
			{"username": "rmehta", "name": "Rohan Mehta", "avatarUrl": null,
			 "mergeRequestInteraction": {"reviewState": "UNREVIEWED"}}
		]}
		""")
		let approvals = try #require(decode(json).mergeRequest?.approvalStatus)
		#expect(approvals.decision == .reviewRequired)
		#expect(approvals.approvedBy.isEmpty)
		#expect(approvals.changesRequestedBy.isEmpty)
	}

	@Test("tiers without approval rules report no required count")
	func noApprovalRules() throws {
		// Approval rules are a paid feature; other tiers send 0 or omit the field,
		// neither of which means "zero approvals needed".
		#expect(try decode(node(#""state": "opened", "approvalsRequired": 0"#))
			.mergeRequest?.approvalStatus.approvalsRequired == nil)
		#expect(try decode(node(#""state": "opened""#))
			.mergeRequest?.approvalStatus.approvalsRequired == nil)
	}

	@Test("prefers the grouped counts, so one reviewer covering several rules counts once")
	func prefersGroupedCounts() throws {
		// The ungrouped pair counts every rule separately, so an MR that two people
		// have fully covered still reads as "2 of 8". The grouped pair collapses
		// rules sharing a section and approvers, which is what the UI should show.
		let json = node("""
		"state": "opened",
		"approved": true,
		"approvalsRequired": 8,
		"approvalsLeft": 6,
		"groupedApprovalsRequired": 2,
		"groupedApprovalsLeft": 0,
		"approvedBy": {"nodes": [
			{"username": "aberg", "name": "Astrid Berg", "avatarUrl": null},
			{"username": "cdupont", "name": "Camille Dupont", "avatarUrl": null}
		]}
		""")
		let approvals = try #require(decode(json).mergeRequest?.approvalStatus)
		#expect(approvals.decision == .approved)
		#expect(approvals.approvalsRequired == 2)
		#expect(approvals.approvalsLeft == 0)
		#expect(approvals.approvalsSatisfied == 2)
	}

	@Test("falls back to the ungrouped counts when grouped ones are absent")
	func fallsBackToUngroupedCounts() throws {
		let json = node("""
		"state": "opened",
		"approved": false,
		"approvalsRequired": 3,
		"approvalsLeft": 1
		""")
		let approvals = try #require(decode(json).mergeRequest?.approvalStatus)
		#expect(approvals.approvalsRequired == 3)
		#expect(approvals.approvalsSatisfied == 2)
	}

	@Test("a user without a name falls back to the username")
	func missingDisplayName() throws {
		let json = node("""
		"state": "opened",
		"approved": true,
		"approvedBy": {"nodes": [{"username": "aberg", "name": null, "avatarUrl": null}]}
		""")
		#expect(try #require(decode(json).mergeRequest?.approvalStatus).approvedBy[0].displayName == "aberg")
	}
}

@Suite("GitHub PR GraphQL response")
struct GitHubPullRequestResponseTests {
	private func decode(_ json: String) throws -> GitHubPullRequestResponse {
		try JSONDecoder().decode(GitHubPullRequestResponse.self, from: Data(json.utf8))
	}

	private func node(_ fields: String) -> String {
		#"{"data": {"repository": {"pullRequests": {"nodes": [{"url": "https://github.com/o/r/pull/7", \#(fields)}]}}}}"#
	}

	@Test("parses a full pull request")
	func fullPullRequest() throws {
		let json = node("""
		"state": "OPEN",
		"isDraft": false,
		"reviewThreads": {"nodes": [
			{"isResolved": false},
			{"isResolved": true},
			{"isResolved": false}
		]}
		""")
		let pullRequest = try #require(decode(json).pullRequest)
		#expect(pullRequest.url == "https://github.com/o/r/pull/7")
		#expect(pullRequest.mappedState == .ready)
		#expect(pullRequest.unresolvedCount == 2)
	}

	@Test("maps PR states")
	func stateMapping() throws {
		#expect(try decode(node(#""state": "MERGED""#)).pullRequest?.mappedState == .merged)
		#expect(try decode(node(#""state": "CLOSED""#)).pullRequest?.mappedState == .closed)
		#expect(try decode(node(#""state": "OPEN", "isDraft": true"#)).pullRequest?.mappedState == .draft)
	}

	@Test("PR without threads reports zero, missing threads report unknown")
	func threadCounts() throws {
		#expect(try decode(node(#""state": "OPEN", "reviewThreads": {"nodes": []}"#)).pullRequest?.unresolvedCount == 0)
		#expect(try decode(node(#""state": "OPEN""#)).pullRequest?.unresolvedCount == nil)
	}

	@Test("missing PR or repository reports none")
	func missingPullRequest() throws {
		#expect(try decode(#"{"data": {"repository": {"pullRequests": {"nodes": []}}}}"#).pullRequest == nil)
		#expect(try decode(#"{"data": {"repository": null}}"#).pullRequest == nil)
		#expect(try decode(#"{"data": null}"#).pullRequest == nil)
	}

	// MARK: - Approvals

	@Test("reviewDecision drives the decision when present")
	func reviewDecisionIsAuthoritative() throws {
		let json = node("""
		"state": "OPEN",
		"reviewDecision": "APPROVED",
		"latestOpinionatedReviews": {"nodes": [
			{"state": "APPROVED", "author": {"login": "aberg", "name": "Astrid Berg",
			 "avatarUrl": "https://avatars.githubusercontent.com/u/1"}}
		]}
		""")
		let approvals = try #require(decode(json).pullRequest?.approvalStatus)
		#expect(approvals.decision == .approved)
		#expect(approvals.approvedBy.map(\.username) == ["aberg"])
		#expect(approvals.approvedBy[0].displayName == "Astrid Berg")
		#expect(approvals.approvedBy[0].avatarURL == "https://avatars.githubusercontent.com/u/1")
		// GitHub never exposes the required-review count on the PR itself.
		#expect(approvals.approvalsRequired == nil)
	}

	@Test("maps every reviewDecision value")
	func reviewDecisionMapping() throws {
		#expect(try decode(node(#""state": "OPEN", "reviewDecision": "CHANGES_REQUESTED""#))
			.pullRequest?.approvalStatus.decision == .changesRequested)
		#expect(try decode(node(#""state": "OPEN", "reviewDecision": "REVIEW_REQUIRED""#))
			.pullRequest?.approvalStatus.decision == .reviewRequired)
	}

	@Test("falls back to the reviews when reviewDecision is null")
	func nullReviewDecisionFallsBackToReviews() throws {
		// GitHub returns null here whenever the repository has no required-reviews
		// branch protection rule, which is the common case for small repos.
		let approvedOnly = node("""
		"state": "OPEN",
		"reviewDecision": null,
		"latestOpinionatedReviews": {"nodes": [
			{"state": "APPROVED", "author": {"login": "aberg", "name": "Astrid Berg", "avatarUrl": null}}
		]}
		""")
		#expect(try decode(approvedOnly).pullRequest?.approvalStatus.decision == .approved)

		let blocked = node("""
		"state": "OPEN",
		"reviewDecision": null,
		"latestOpinionatedReviews": {"nodes": [
			{"state": "APPROVED", "author": {"login": "aberg", "name": "Astrid Berg", "avatarUrl": null}},
			{"state": "CHANGES_REQUESTED", "author": {"login": "rmehta", "name": "Rohan Mehta", "avatarUrl": null}}
		]}
		""")
		let approvals = try #require(decode(blocked).pullRequest?.approvalStatus)
		#expect(approvals.decision == .changesRequested)
		#expect(approvals.changesRequestedBy.map(\.username) == ["rmehta"])
		#expect(approvals.approvedBy.map(\.username) == ["aberg"])
	}

	@Test("a PR with no reviews and no decision awaits review")
	func noReviewsAtAll() throws {
		#expect(try decode(node(#""state": "OPEN""#)).pullRequest?.approvalStatus.decision == .reviewRequired)
		#expect(
			try decode(node(#""state": "OPEN", "latestOpinionatedReviews": {"nodes": []}"#))
				.pullRequest?.approvalStatus.decision == .reviewRequired
		)
	}

	@Test("an author without a name falls back to the login")
	func missingDisplayName() throws {
		let json = node("""
		"state": "OPEN",
		"reviewDecision": "APPROVED",
		"latestOpinionatedReviews": {"nodes": [
			{"state": "APPROVED", "author": {"login": "aberg", "avatarUrl": null}}
		]}
		""")
		#expect(try #require(decode(json).pullRequest?.approvalStatus).approvedBy[0].displayName == "aberg")
	}
}
