import Testing
@testable import GitCore

@Suite("GitBranchNameSanitizer")
struct GitBranchNameSanitizerTests {
	@Test("spaces become underscores")
	func spacesBecomeUnderscores() {
		#expect(GitBranchNameSanitizer.sanitize("fix login bug") == "fix_login_bug")
	}

	@Test("each whitespace character maps to exactly one underscore")
	func oneUnderscorePerWhitespaceCharacter() {
		#expect(GitBranchNameSanitizer.sanitize("fix  bug") == "fix__bug")
		#expect(GitBranchNameSanitizer.sanitize("fix ") == "fix_")
	}

	@Test("leading whitespace is dropped, not turned into underscores")
	func leadingWhitespaceIsDropped() {
		#expect(GitBranchNameSanitizer.sanitize("  fix") == "fix")
		#expect(GitBranchNameSanitizer.sanitize("\t fix bug") == "fix_bug")
	}

	@Test("a name of only whitespace sanitizes to nothing, so it cannot be submitted")
	func onlyWhitespaceIsEmpty() {
		#expect(GitBranchNameSanitizer.sanitize("   ") == "")
		#expect(GitBranchNameSanitizer.sanitize(" \t\n") == "")
	}

	@Test("tabs and newlines from pasted text are treated like spaces")
	func tabsAndNewlinesBecomeUnderscores() {
		#expect(GitBranchNameSanitizer.sanitize("fix\tlogin\nbug") == "fix_login_bug")
	}

	@Test("names without whitespace are returned unchanged")
	func noWhitespaceIsUnchanged() {
		#expect(GitBranchNameSanitizer.sanitize("feature/MOB-123_login") == "feature/MOB-123_login")
		#expect(GitBranchNameSanitizer.sanitize("") == "")
	}
}
