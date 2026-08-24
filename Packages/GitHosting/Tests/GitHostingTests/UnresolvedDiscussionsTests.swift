import Foundation
import Testing
@testable import GitHosting

@Suite("Unresolved discussion counts")
struct UnresolvedDiscussionsTests {
	// MARK: - GitLab GraphQL response

	private func decodeGitLab(_ json: String) throws -> GitLabDiscussionCountsResponse {
		try JSONDecoder().decode(GitLabDiscussionCountsResponse.self, from: Data(json.utf8))
	}

	@Test("GitLab: unresolved is resolvable minus resolved")
	func gitLabSubtractsResolved() throws {
		let json = """
		{"data": {"project": {"mergeRequest": {
			"resolvableDiscussionsCount": 5,
			"resolvedDiscussionsCount": 3
		}}}}
		"""
		#expect(try decodeGitLab(json).unresolvedCount == 2)
	}

	@Test("GitLab: fully resolved MR reports zero")
	func gitLabFullyResolved() throws {
		let json = """
		{"data": {"project": {"mergeRequest": {
			"resolvableDiscussionsCount": 4,
			"resolvedDiscussionsCount": 4
		}}}}
		"""
		#expect(try decodeGitLab(json).unresolvedCount == 0)
	}

	@Test("GitLab: resolved exceeding resolvable clamps to zero")
	func gitLabClampsNegative() throws {
		let json = """
		{"data": {"project": {"mergeRequest": {
			"resolvableDiscussionsCount": 1,
			"resolvedDiscussionsCount": 2
		}}}}
		"""
		#expect(try decodeGitLab(json).unresolvedCount == 0)
	}

	@Test("GitLab: missing MR or project reports unknown")
	func gitLabMissingMergeRequest() throws {
		#expect(try decodeGitLab(#"{"data": {"project": {"mergeRequest": null}}}"#).unresolvedCount == nil)
		#expect(try decodeGitLab(#"{"data": {"project": null}}"#).unresolvedCount == nil)
		#expect(try decodeGitLab(#"{"data": null}"#).unresolvedCount == nil)
	}

	// MARK: - GitHub GraphQL response

	private func decodeGitHub(_ json: String) throws -> GitHubReviewThreadsResponse {
		try JSONDecoder().decode(GitHubReviewThreadsResponse.self, from: Data(json.utf8))
	}

	@Test("GitHub: counts only unresolved threads")
	func gitHubCountsUnresolved() throws {
		let json = """
		{"data": {"repository": {"pullRequest": {"reviewThreads": {"nodes": [
			{"isResolved": false},
			{"isResolved": true},
			{"isResolved": false},
			{"isResolved": true}
		]}}}}}
		"""
		#expect(try decodeGitHub(json).unresolvedCount == 2)
	}

	@Test("GitHub: PR without threads reports zero")
	func gitHubNoThreads() throws {
		let json = #"{"data": {"repository": {"pullRequest": {"reviewThreads": {"nodes": []}}}}}"#
		#expect(try decodeGitHub(json).unresolvedCount == 0)
	}

	@Test("GitHub: missing PR or repository reports unknown")
	func gitHubMissingPullRequest() throws {
		#expect(try decodeGitHub(#"{"data": {"repository": {"pullRequest": null}}}"#).unresolvedCount == nil)
		#expect(try decodeGitHub(#"{"data": {"repository": null}}"#).unresolvedCount == nil)
		#expect(try decodeGitHub(#"{"data": null}"#).unresolvedCount == nil)
	}
}
