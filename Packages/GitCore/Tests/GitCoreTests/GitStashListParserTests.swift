import Testing
@testable import GitCore

@Suite("GitStashListParser")
struct GitStashListParserTests {

	// MARK: - Parsing

	@Test("a plain `git stash` entry yields its reference, branch and commit subject")
	func parsesWIPEntry() {
		let entries = GitStashListParser.parse("stash@{0}: WIP on feature/login: abc1234 Add login form")

		#expect(entries == [
			GitStashEntry(reference: "stash@{0}", branch: "feature/login", message: "abc1234 Add login form"),
		])
	}

	@Test("a `git stash push -m` entry yields the custom message")
	func parsesOnEntry() {
		let entries = GitStashListParser.parse("stash@{0}: On main: half-finished refactor")

		#expect(entries == [
			GitStashEntry(reference: "stash@{0}", branch: "main", message: "half-finished refactor"),
		])
	}

	@Test("entries keep git's newest-first order and their own indices")
	func parsesMultipleEntries() {
		let output = """
		stash@{0}: WIP on main: 1111111 Newest
		stash@{1}: On feature: middle
		stash@{2}: WIP on main: 3333333 Oldest
		"""

		#expect(GitStashListParser.parse(output) == [
			GitStashEntry(reference: "stash@{0}", branch: "main", message: "1111111 Newest"),
			GitStashEntry(reference: "stash@{1}", branch: "feature", message: "middle"),
			GitStashEntry(reference: "stash@{2}", branch: "main", message: "3333333 Oldest"),
		])
	}

	@Test("a slash in the branch name is not mistaken for the end of the branch")
	func parsesBranchWithSlashes() {
		let entries = GitStashListParser.parse("stash@{0}: WIP on release/2026.09/hotfix: abc1234 Patch")

		#expect(entries.first?.branch == "release/2026.09/hotfix")
	}

	@Test("a colon in the message does not extend the branch name")
	func colonInMessageDoesNotLeakIntoBranch() {
		let entries = GitStashListParser.parse("stash@{0}: WIP on main: abc1234 fix: handle empty input")

		#expect(entries.first?.branch == "main")
		#expect(entries.first?.message == "abc1234 fix: handle empty input")
	}

	@Test("a message that looks like a branch prefix is not read as one")
	func messageImitatingAPrefixIsNotABranch() {
		// `git stash push -m "On main: fixup"` while on `feature` — the old substring
		// search saw "On main:" in the line and reported a stash on main.
		let entries = GitStashListParser.parse("stash@{0}: On feature: On main: fixup")

		#expect(entries.first?.branch == "feature")
		#expect(entries.first?.message == "On main: fixup")
	}

	@Test("a stash taken on a detached HEAD reports no branch")
	func detachedHeadHasNoBranch() {
		let entries = GitStashListParser.parse("stash@{0}: WIP on (no branch): abc1234 Detached work")

		#expect(entries.first?.branch == nil)
		#expect(entries.first?.reference == "stash@{0}")
	}

	@Test("an entry stored with an arbitrary message keeps the message and reports no branch")
	func storedEntryWithoutBranchPrefix() {
		let entries = GitStashListParser.parse("stash@{0}: custom stash from a script")

		#expect(entries == [
			GitStashEntry(reference: "stash@{0}", branch: nil, message: "custom stash from a script"),
		])
	}

	@Test("empty output produces no entries")
	func emptyOutput() {
		#expect(GitStashListParser.parse("").isEmpty)
		#expect(GitStashListParser.parse("\n\n").isEmpty)
	}

	@Test("lines that are not stash references are skipped")
	func nonStashLinesAreSkipped() {
		let output = """
		warning: something git printed: on stdout
		stash@{0}: WIP on main: abc1234 Real entry
		"""

		#expect(GitStashListParser.parse(output) == [
			GitStashEntry(reference: "stash@{0}", branch: "main", message: "abc1234 Real entry"),
		])
	}

	// MARK: - Selecting an entry

	@Test("the newest stash on the branch wins, not the newest stash overall")
	func newestEntryPrefersTheBranch() {
		let entries = GitStashListParser.parse("""
		stash@{0}: WIP on other: 1111111 Someone else's worktree
		stash@{1}: WIP on main: 2222222 Newer main stash
		stash@{2}: WIP on main: 3333333 Older main stash
		""")

		#expect(GitStashListParser.newestEntry(on: "main", in: entries)?.reference == "stash@{1}")
	}

	@Test("a branch with no stash matches nothing")
	func noEntryForUnstashedBranch() {
		let entries = GitStashListParser.parse("stash@{0}: WIP on main: abc1234 Work")

		#expect(GitStashListParser.newestEntry(on: "feature", in: entries) == nil)
	}

	@Test("a branch name that is a prefix of another branch's does not match it")
	func prefixBranchDoesNotMatch() {
		let entries = GitStashListParser.parse("stash@{0}: WIP on main-hotfix: abc1234 Work")

		#expect(GitStashListParser.newestEntry(on: "main", in: entries) == nil)
	}

	@Test("an empty branch — a row whose status has not landed — matches nothing")
	func emptyBranchMatchesNothing() {
		let entries = GitStashListParser.parse("stash@{0}: WIP on (no branch): abc1234 Work")

		#expect(GitStashListParser.newestEntry(on: "", in: entries) == nil)
	}
}
