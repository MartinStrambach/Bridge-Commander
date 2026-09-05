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
		#expect(GitBranchNameSanitizer.sanitize(" fix ") == "_fix_")
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
