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
}
