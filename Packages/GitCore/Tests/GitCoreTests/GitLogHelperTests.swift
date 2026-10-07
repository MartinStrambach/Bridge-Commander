import Foundation
import Testing
@testable import GitCore

@Suite("GitLogHelper")
struct GitLogHelperTests {
	private static let fs = "\u{1F}"
	private static let rs = "\u{1E}"

	@Test("parses commits with fields, parents, and timestamp")
	func parsesCommits() {
		let output = [
			"aaa111\(Self.fs)bbb222 ccc333\(Self.fs)Alice\(Self.fs)1700000000\(Self.fs)\(Self.fs)Merge feature\(Self.rs)",
			"\nbbb222\(Self.fs)ddd444\(Self.fs)Bob\(Self.fs)1690000000\(Self.fs)\(Self.fs)Fix bug\(Self.rs)"
		].joined()

		let commits = GitLogHelper.parse(logOutput: output)

		#expect(commits.count == 2)
		#expect(commits[0].hash == "aaa111")
		#expect(commits[0].parents == ["bbb222", "ccc333"])
		#expect(commits[0].author == "Alice")
		#expect(commits[0].date == Date(timeIntervalSince1970: 1_700_000_000))
		#expect(commits[0].subject == "Merge feature")
		#expect(commits[0].isMerge)
		#expect(commits[1].parents == ["ddd444"])
		#expect(!commits[1].isMerge)
	}

	@Test("parses root commit with no parents and empty output")
	func parsesRootAndEmpty() {
		let output = "aaa111\(Self.fs)\(Self.fs)Alice\(Self.fs)1700000000\(Self.fs)\(Self.fs)Initial commit\(Self.rs)"

		let commits = GitLogHelper.parse(logOutput: output)
		#expect(commits.count == 1)
		#expect(commits[0].parents.isEmpty)

		#expect(GitLogHelper.parse(logOutput: "").isEmpty)
		#expect(GitLogHelper.parse(logOutput: "\n").isEmpty)
	}

	@Test("parses full decorations into typed refs")
	func parsesDecorations() {
		let refs = GitLogHelper.parseDecorations(
			"HEAD -> refs/heads/main, refs/remotes/origin/main, tag: refs/tags/v1.0, refs/heads/feature/x"
		)

		#expect(refs == [
			GitCommitRef(name: "main", kind: .localBranch, isHead: true),
			GitCommitRef(name: "origin/main", kind: .remoteBranch),
			GitCommitRef(name: "v1.0", kind: .tag),
			GitCommitRef(name: "feature/x", kind: .localBranch)
		])
	}

	@Test("parses detached HEAD and skips unknown refs")
	func parsesDetachedHeadAndSkipsUnknown() {
		let refs = GitLogHelper.parseDecorations("HEAD, refs/stash, refs/remotes/origin/HEAD")

		#expect(refs == [GitCommitRef(name: "HEAD", kind: .detachedHead, isHead: true)])
		#expect(refs[0].isHead)

		#expect(GitLogHelper.parseDecorations("").isEmpty)
	}

	@Test("commit with head ref reports isHead")
	func headDetection() {
		let commits = GitLogHelper.parse(
			logOutput: "aaa\(Self.fs)\(Self.fs)A\(Self.fs)0\(Self.fs)HEAD -> refs/heads/main\(Self.fs)x\(Self.rs)"
		)

		#expect(commits.count == 1)
		#expect(commits[0].isHead)
		#expect(commits[0].refs == [GitCommitRef(name: "main", kind: .localBranch, isHead: true)])
	}

	// MARK: - Search

	@Test("a blank query is no search; a query is trimmed")
	func searchTrimsAndRejectsBlankQueries() {
		#expect(GitLogSearch(field: .message, query: "") == nil)
		#expect(GitLogSearch(field: .message, query: "  \n") == nil)
		#expect(GitLogSearch(field: .author, query: "  alice ")?.query == "alice")
	}

	@Test("no search logs the whole history")
	func argumentsWithoutSearch() {
		let arguments = GitLogHelper.logArguments(limit: 300, search: nil)

		#expect(arguments.contains("--max-count=300"))
		#expect(!arguments.contains("--"))
		#expect(!arguments.contains { $0.hasPrefix("--grep") || $0.hasPrefix("--author") || $0.hasPrefix("-S") })
	}

	@Test("message, author and content searches are literal and case-insensitive")
	func argumentsForTextSearches() throws {
		let message = GitLogHelper.logArguments(limit: 10, search: try search(.message, "fix("))
		#expect(message.suffix(3) == ["--regexp-ignore-case", "--fixed-strings", "--grep=fix("])

		let author = GitLogHelper.logArguments(limit: 10, search: try search(.author, "Alice"))
		#expect(author.suffix(3) == ["--regexp-ignore-case", "--fixed-strings", "--author=Alice"])

		let content = GitLogHelper.logArguments(limit: 10, search: try search(.content, "runGit"))
		#expect(content.suffix(2) == ["--regexp-ignore-case", "-SrunGit"])
	}

	@Test("a path search rewrites parents and ends with its pathspecs")
	func argumentsForPathSearch() throws {
		let arguments = GitLogHelper.logArguments(limit: 10, search: try search(.path, "GitCore"))
		let separator = try #require(arguments.firstIndex(of: "--"))

		#expect(arguments[..<separator].contains("--parents"))
		#expect(Array(arguments[(separator + 1)...]) == GitLogHelper.pathspecs(for: "GitCore"))
	}

	@Test("pathspecs match a file, a directory and a root-relative path, ignoring outer slashes")
	func pathspecs() {
		#expect(GitLogHelper.pathspecs(for: "/Packages/GitCore/") == [
			":(icase)Packages/GitCore",
			":(glob,icase)**/*Packages/GitCore*",
			":(glob,icase)**/*Packages/GitCore*/**"
		])
	}

	@Test("only a path search has its parents rewritten by git")
	func rewritesParents() {
		let rewriting = GitLogSearch.Field.allCases.filter { GitLogSearch(field: $0, query: "x")?.rewritesParents == true }
		#expect(rewriting == [.path])
	}

	@Test("pruning keeps graph parents that are listed, and the real parents untouched")
	func pruningUnlistedGraphParents() {
		let commits = [
			GitLogCommit(hash: "aaa", parents: ["bbb", "ccc"], author: "A", date: .distantPast, refs: [], subject: "Merge"),
			GitLogCommit(hash: "ccc", parents: ["ddd"], author: "A", date: .distantPast, refs: [], subject: "Side")
		]

		let pruned = GitLogHelper.pruningUnlistedGraphParents(commits)

		#expect(pruned[0].graphParents == ["ccc"])
		#expect(pruned[0].parents == ["bbb", "ccc"])
		#expect(pruned[0].isMerge)
		#expect(pruned[1].graphParents.isEmpty)
	}

	@Test("graph parents default to the real parents")
	func graphParentsDefault() {
		let commit = GitLogCommit(hash: "aaa", parents: ["bbb"], author: "A", date: .distantPast, refs: [], subject: "x")
		#expect(commit.graphParents == ["bbb"])
	}

	/// A non-optional return type, so `#require` unwraps the search rather than wrapping it again for
	/// `logArguments`'s optional parameter (which made it unable to fail).
	private func search(_ field: GitLogSearch.Field, _ query: String) throws -> GitLogSearch {
		try #require(GitLogSearch(field: field, query: query))
	}
}
