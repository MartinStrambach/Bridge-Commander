import Foundation
import Testing
@testable import GitHosting

@Suite("Open PR/MR listing responses")
struct OpenPullRequestsParsingTests {
	@Test("GitHub: maps PRs and leaves out those from forks")
	func gitHub() throws {
		let json = Data("""
		{"data": {"repository": {"pullRequests": {"nodes": [
		  {"number": 12, "title": "Fix crash", "url": "https://github.com/o/r/pull/12", "isDraft": true,
		   "headRefName": "fix_crash_MOB-1", "isCrossRepository": false, "author": {"login": "martin"}},
		  {"number": 13, "title": "From a fork", "url": "https://github.com/o/r/pull/13", "isDraft": false,
		   "headRefName": "main", "isCrossRepository": true, "author": {"login": "someone"}},
		  {"number": 14, "title": "Ghost author", "url": "https://github.com/o/r/pull/14",
		   "headRefName": "cleanup", "isCrossRepository": false, "author": null}
		]}}}}
		""".utf8)
		let pullRequests = try #require(try JSONDecoder().decode(GitHubOpenPullRequestsResponse.self, from: json).pullRequests)
		#expect(pullRequests == [
			OpenPullRequest(
				number: 12, title: "Fix crash", sourceBranch: "fix_crash_MOB-1", author: "martin",
				url: "https://github.com/o/r/pull/12", isDraft: true, provider: .github
			),
			OpenPullRequest(
				number: 14, title: "Ghost author", sourceBranch: "cleanup", author: nil,
				url: "https://github.com/o/r/pull/14", isDraft: false, provider: .github
			),
		])
		#expect(pullRequests[0].reference == "#12")
	}

	@Test("GitHub: a repository the token cannot see is not an empty list")
	func gitHubInvisibleRepository() throws {
		let json = Data(#"{"data": {"repository": null}}"#.utf8)
		#expect(try JSONDecoder().decode(GitHubOpenPullRequestsResponse.self, from: json).pullRequests == nil)
	}

	@Test("GitLab: maps MRs, reads the string iid and leaves out those from forks")
	func gitLab() throws {
		let json = Data("""
		{"data": {"project": {"mergeRequests": {"nodes": [
		  {"iid": "7", "title": "Login", "webUrl": "https://gitlab.com/g/p/-/merge_requests/7", "draft": false,
		   "sourceBranch": "login_MOB-2", "sourceProjectId": 5, "targetProjectId": 5, "author": {"username": "ms"}},
		  {"iid": "8", "title": "Fork", "webUrl": "https://gitlab.com/g/p/-/merge_requests/8", "draft": false,
		   "sourceBranch": "master", "sourceProjectId": 9, "targetProjectId": 5, "author": {"username": "x"}}
		]}}}}
		""".utf8)
		let mergeRequests = try #require(try JSONDecoder().decode(GitLabOpenMergeRequestsResponse.self, from: json).mergeRequests)
		#expect(mergeRequests == [
			OpenPullRequest(
				number: 7, title: "Login", sourceBranch: "login_MOB-2", author: "ms",
				url: "https://gitlab.com/g/p/-/merge_requests/7", isDraft: false, provider: .gitlab
			),
		])
		#expect(mergeRequests[0].reference == "!7")
	}

	@Test("GitLab: a project the token cannot see is not an empty list")
	func gitLabInvisibleProject() throws {
		let json = Data(#"{"data": {"project": null}}"#.utf8)
		#expect(try JSONDecoder().decode(GitLabOpenMergeRequestsResponse.self, from: json).mergeRequests == nil)
	}
}
