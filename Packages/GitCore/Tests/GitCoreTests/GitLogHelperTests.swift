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
}
