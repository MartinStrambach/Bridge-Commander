import Foundation
import Testing
@testable import GitHosting

@Suite("Open PR/MR search")
struct OpenPullRequestSearchTests {
	// MARK: - Query

	@Test("blank text asks for nothing")
	func blankQuery() {
		#expect(OpenPullRequestQuery("") == nil)
		#expect(OpenPullRequestQuery("  \n") == nil)
	}

	@Test("words are searched in titles and descriptions; one word is also tried as a branch")
	func wordsQuery() throws {
		let words = try #require(OpenPullRequestQuery("  country ranking "))
		#expect(words.filter == "country ranking")
		#expect(words.searchText == "country ranking")
		#expect(words.number == nil)
		#expect(words.branch == nil)

		let branch = try #require(OpenPullRequestQuery("feature/ai_factory_MOB-5324"))
		#expect(branch.searchText == "feature/ai_factory_MOB-5324")
		#expect(branch.branch == "feature/ai_factory_MOB-5324")
	}

	@Test("plain digits name a number and are also searched; !12 and #12 only name it")
	func numberQuery() throws {
		let digits = try #require(OpenPullRequestQuery("6407"))
		#expect(digits.number == 6407)
		#expect(digits.searchText == "6407")
		#expect(digits.branch == nil)

		for reference in ["!6407", "#6407"] {
			let query = try #require(OpenPullRequestQuery(reference))
			#expect(query.number == 6407)
			#expect(query.searchText == nil)
			#expect(query.branch == nil)
		}
	}

	@Test("a pasted PR/MR link names its number")
	func linkQuery() throws {
		let links = [
			"https://gitlab.com/livesport/flashscore/mobi/flashscore/-/merge_requests/6407",
			"https://gitlab.com/g/p/-/merge_requests/6407/diffs",
			"https://github.com/o/r/pull/6407/files",
			"https://github.com/o/r/pull/6407?w=1",
		]
		for link in links {
			let query = try #require(OpenPullRequestQuery(link))
			#expect(query.number == 6407, "\(link)")
			#expect(query.searchText == nil)
			#expect(query.branch == nil)
		}
		// Not a PR/MR link: searched as text.
		#expect(OpenPullRequestQuery("https://github.com/o/r/pulls")?.number == nil)
	}

	@Test("a listed PR/MR matches by title, branch, reference, author or the number the text names")
	func localMatching() throws {
		let pullRequest = OpenPullRequest(
			number: 6407, title: "Show error state", sourceBranch: "feature/MOB-5324", author: "mobi-factory",
			url: "https://gitlab.com/g/p/-/merge_requests/6407", isDraft: false, provider: .gitlab
		)
		for text in ["error STATE", "mob-5324", "!64", "6407", "factory", "https://gitlab.com/g/p/-/merge_requests/6407"] {
			#expect(try #require(OpenPullRequestQuery(text)).matches(pullRequest), "\(text)")
		}
		#expect(try #require(OpenPullRequestQuery("#6407")).matches(pullRequest))
		#expect(!(try #require(OpenPullRequestQuery("login")).matches(pullRequest)))
	}

	// MARK: - Responses

	@Test("GitHub: the named open PR, then the branch's, then the text's, each once; closed, non-PR and other repositories' hits dropped")
	func gitHubSearch() throws {
		let json = Data("""
		{"data": {
		  "repository": {"id": "R", "byNumber": {"number": 12, "title": "Named", "url": "https://github.com/o/r/pull/12",
		    "isDraft": false, "headRefName": "named", "isCrossRepository": false, "viewerDidAuthor": true,
		    "author": {"login": "martin"}, "state": "OPEN"}},
		  "byBranch": {"nodes": [{"number": 20, "title": "Branch", "url": "https://github.com/o/r/pull/20",
		    "isDraft": true, "headRefName": "fix", "isCrossRepository": false, "author": {"login": "x"},
		    "baseRepository": {"nameWithOwner": "O/R"}}]},
		  "bySearch": {"nodes": [
		    {"number": 12, "title": "Named", "url": "https://github.com/o/r/pull/12", "isDraft": false,
		     "headRefName": "named", "isCrossRepository": false, "author": {"login": "martin"},
		     "baseRepository": {"nameWithOwner": "o/r"}},
		    {},
		    {"number": 40, "title": "Other repository", "url": "https://github.com/x/y/pull/40", "isDraft": false,
		     "headRefName": "fix", "isCrossRepository": false, "author": null, "baseRepository": {"nameWithOwner": "x/y"}},
		    {"number": 30, "title": "Text", "url": "https://github.com/o/r/pull/30", "isDraft": false,
		     "headRefName": "main", "isCrossRepository": true, "headRepositoryOwner": {"login": "fork"}, "author": null,
		     "baseRepository": {"nameWithOwner": "o/r"}}
		  ]}
		}}
		""".utf8)
		let pullRequests = try #require(try JSONDecoder().decode(GitHubPullRequestSearchResponse.self, from: json).pullRequests(in: "o/r"))
		#expect(pullRequests.map(\.number) == [12, 20, 30])
		#expect(pullRequests[0].isAuthoredByViewer)
		#expect(pullRequests[1].isDraft)
		#expect(pullRequests[2].isFromFork && pullRequests[2].forkOwner == "fork")

		let closed = Data("""
		{"data": {"repository": {"id": "R", "byNumber": {"number": 12, "title": "Named",
		  "url": "https://github.com/o/r/pull/12", "headRefName": "named", "state": "MERGED"}}}}
		""".utf8)
		#expect(try JSONDecoder().decode(GitHubPullRequestSearchResponse.self, from: closed).pullRequests(in: "o/r") == [])

		// A number that is an issue: null beside GitHub's NOT_FOUND error.
		let notAPullRequest = Data(#"{"data": {"repository": {"id": "R", "byNumber": null}}, "errors": [{"type": "NOT_FOUND"}]}"#.utf8)
		#expect(try JSONDecoder().decode(GitHubPullRequestSearchResponse.self, from: notAPullRequest).pullRequests(in: "o/r") == [])
	}

	@Test("GitHub: a search hit of an unexpected shape fails the answer rather than vanishing")
	func gitHubSearchDrift() {
		let json = Data(#"{"data": {"repository": {"id": "R"}, "bySearch": {"nodes": [{"number": "12"}]}}}"#.utf8)
		#expect(throws: DecodingError.self) {
			try JSONDecoder().decode(GitHubPullRequestSearchResponse.self, from: json)
		}
	}

	@Test("GitHub: a repository the token cannot see is not an empty result")
	func gitHubSearchInvisibleRepository() throws {
		let json = Data(#"{"data": {"repository": null, "bySearch": {"nodes": []}}}"#.utf8)
		#expect(try JSONDecoder().decode(GitHubPullRequestSearchResponse.self, from: json).pullRequests(in: "o/r") == nil)
	}

	@Test("GitLab: the named MR, then the branch's, then the text's, each once, the viewer's own marked")
	func gitLabSearch() throws {
		let json = Data("""
		{"data": {"currentUser": {"username": "ms"}, "project": {"id": "P",
		  "byNumber": {"nodes": [{"iid": "6407", "title": "Named", "webUrl": "https://gitlab.com/g/p/-/merge_requests/6407",
		    "draft": false, "sourceBranch": "feature/MOB-5324", "sourceProjectId": 5, "targetProjectId": 5,
		    "author": {"username": "bot"}}]},
		  "byBranch": {"nodes": [{"iid": "6407", "title": "Named", "webUrl": "https://gitlab.com/g/p/-/merge_requests/6407",
		    "draft": false, "sourceBranch": "feature/MOB-5324", "sourceProjectId": 5, "targetProjectId": 5,
		    "author": {"username": "bot"}}]},
		  "bySearch": {"nodes": [{"iid": "6303", "title": "Text", "webUrl": "https://gitlab.com/g/p/-/merge_requests/6303",
		    "draft": true, "sourceBranch": "other", "sourceProjectId": 9, "targetProjectId": 5,
		    "sourceProject": {"fullPath": "x/p"}, "author": {"username": "ms"}}]}
		}}}
		""".utf8)
		let mergeRequests = try #require(try JSONDecoder().decode(GitLabMergeRequestSearchResponse.self, from: json).mergeRequests)
		#expect(mergeRequests == [
			OpenPullRequest(
				number: 6407, title: "Named", sourceBranch: "feature/MOB-5324", author: "bot",
				url: "https://gitlab.com/g/p/-/merge_requests/6407", isDraft: false, provider: .gitlab
			),
			OpenPullRequest(
				number: 6303, title: "Text", sourceBranch: "other", author: "ms",
				url: "https://gitlab.com/g/p/-/merge_requests/6303", isDraft: true, provider: .gitlab,
				isFromFork: true, forkOwner: "x", isAuthoredByViewer: true
			),
		])
	}

	@Test("GitLab: a project the token cannot see is not an empty result")
	func gitLabSearchInvisibleProject() throws {
		let json = Data(#"{"data": {"currentUser": {"username": "ms"}, "project": null}}"#.utf8)
		#expect(try JSONDecoder().decode(GitLabMergeRequestSearchResponse.self, from: json).mergeRequests == nil)
	}
}
