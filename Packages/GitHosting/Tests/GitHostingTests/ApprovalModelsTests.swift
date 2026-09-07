import Testing

@testable import GitHosting

@Suite("Reviewer monogram")
struct ReviewerInitialsTests {
	@Test("Takes the first letter of the first two words")
	func multiWordDisplayName() {
		let reviewer = Reviewer(username: "aberg", displayName: "Astrid Berg")
		#expect(reviewer.initials == "AB")
	}

	@Test("Stops at two letters for longer names")
	func threeWordDisplayName() {
		let reviewer = Reviewer(username: "mvdb", displayName: "Marieke van den Berg")
		#expect(reviewer.initials == "MV")
	}

	@Test("Uses a single letter for a one-word display name")
	func singleWordDisplayName() {
		let reviewer = Reviewer(username: "prisma", displayName: "Prisma")
		#expect(reviewer.initials == "P")
	}

	@Test("Splits on dots, underscores and dashes as well as spaces")
	func punctuationSeparatedName() {
		#expect(Reviewer(username: "x", displayName: "astrid.berg").initials == "AB")
		#expect(Reviewer(username: "x", displayName: "astrid_berg").initials == "AB")
		#expect(Reviewer(username: "x", displayName: "astrid-berg").initials == "AB")
	}

	@Test("Falls back to the username when the display name has no letters")
	func emptyDisplayNameFallsBackToUsername() {
		#expect(Reviewer(username: "rmehta", displayName: "").initials == "R")
		#expect(Reviewer(username: "rohan mehta", displayName: "🎉").initials == "RM")
	}

	@Test("Falls back to a placeholder when neither field has letters")
	func noLettersAnywhere() {
		#expect(Reviewer(username: "🎉", displayName: "").initials == "?")
	}

	@Test("Handles non-ASCII names")
	func nonASCIIName() {
		#expect(Reviewer(username: "x", displayName: "Žofie Šťastná").initials == "ŽŠ")
	}

	@Test("Skips leading non-letters within a word")
	func leadingPunctuationWithinWord() {
		#expect(Reviewer(username: "x", displayName: "(astrid) berg").initials == "AB")
	}
}

@Suite("Reviewer color index")
struct ReviewerColorIndexTests {
	@Test("Is stable for a given username")
	func isDeterministic() {
		let first = Reviewer(username: "astrid", displayName: "Astrid Berg").colorIndex
		let second = Reviewer(username: "astrid", displayName: "Someone Else").colorIndex
		#expect(first == second)
	}

	@Test("Is pinned to known values, so avatars keep their color across launches")
	func matchesKnownValues() {
		// Hard-coded rather than merely compared to itself: `hashValue` would pass a
		// same-process equality check while still changing on every app launch.
		#expect(Reviewer(username: "astrid", displayName: "").colorIndex == 6)
		#expect(Reviewer(username: "cdupont", displayName: "").colorIndex == 2)
		#expect(Reviewer(username: "rmehta", displayName: "").colorIndex == 6)
	}

	@Test("Stays inside the palette")
	func staysInRange() {
		for name in ["a", "bb", "ccc", "astrid", "", "🎉", "a-very-long-username-here"] {
			let index = Reviewer(username: name, displayName: "").colorIndex
			#expect(index >= 0)
			#expect(index < Reviewer.colorCount)
		}
	}
}

@Suite("Reviewer avatar sizing")
struct ReviewerAvatarSizingTests {
	private func reviewer(_ avatarURL: String?) -> Reviewer {
		Reviewer(username: "aberg", displayName: "Astrid Berg", avatarURL: avatarURL)
	}

	@Test("GitLab uploads use the width parameter")
	func gitLabUsesWidth() {
		let url = reviewer("https://gitlab.com/uploads/-/system/user/avatar/1/a.png").avatarURL(pixels: 48)
		#expect(url?.absoluteString == "https://gitlab.com/uploads/-/system/user/avatar/1/a.png?width=48")
	}

	@Test("GitHub and Gravatar use the s parameter")
	func othersUseS() {
		#expect(
			reviewer("https://avatars.githubusercontent.com/u/1").avatarURL(pixels: 48)?.absoluteString
				== "https://avatars.githubusercontent.com/u/1?s=48"
		)
		#expect(
			reviewer("https://secure.gravatar.com/avatar/abc").avatarURL(pixels: 48)?.absoluteString
				== "https://secure.gravatar.com/avatar/abc?s=48"
		)
	}

	@Test("Preserves an existing query, such as GitLab's cache buster")
	func preservesExistingQuery() {
		let url = reviewer("https://gitlab.com/uploads/-/system/user/avatar/1/a.png?v=123")
			.avatarURL(pixels: 48)
		#expect(url?.absoluteString == "https://gitlab.com/uploads/-/system/user/avatar/1/a.png?v=123&width=48")
	}

	@Test("Replaces a size the host already put there rather than adding a second one")
	func replacesExistingSize() {
		let url = reviewer("https://avatars.githubusercontent.com/u/1?s=80&v=4").avatarURL(pixels: 48)
		#expect(url?.absoluteString == "https://avatars.githubusercontent.com/u/1?v=4&s=48")
	}

	@Test("No avatar yields nil")
	func missingAvatar() {
		#expect(reviewer(nil).avatarURL(pixels: 48) == nil)
	}
}

@Suite("Approval progress")
struct ApprovalProgressTests {
	@Test("Counts covered rules, not distinct approvers")
	func derivesFromApprovalsLeft() {
		// The case that motivated this: 8 rules, 2 people, but those 2 cover
		// everything. Counting approvers would report 2 of 8 on a satisfied MR.
		let status = ApprovalStatus(
			decision: .approved,
			approvedBy: [
				Reviewer(username: "a", displayName: "A"),
				Reviewer(username: "b", displayName: "B"),
			],
			approvalsRequired: 8,
			approvalsLeft: 0
		)
		#expect(status.approvalsSatisfied == 8)
	}

	@Test("Reports partial progress")
	func partialProgress() {
		let status = ApprovalStatus(decision: .reviewRequired, approvalsRequired: 4, approvalsLeft: 3)
		#expect(status.approvalsSatisfied == 1)
	}

	@Test("Clamps at zero if left ever exceeds required")
	func clamps() {
		let status = ApprovalStatus(decision: .reviewRequired, approvalsRequired: 2, approvalsLeft: 5)
		#expect(status.approvalsSatisfied == 0)
	}

	@Test("Reports unknown without both counts")
	func missingCounts() {
		#expect(ApprovalStatus(decision: .approved).approvalsSatisfied == nil)
		#expect(ApprovalStatus(decision: .approved, approvalsRequired: 3).approvalsSatisfied == nil)
		#expect(ApprovalStatus(decision: .approved, approvalsLeft: 1).approvalsSatisfied == nil)
	}

	@Test("Requiring zero approvals is not a fraction and not an unknown count")
	func zeroRequired() {
		let none = ApprovalStatus(decision: .approved, approvalsRequired: 0, approvalsLeft: 0)
		#expect(none.requiresNoApprovals)
		// Nothing should be able to render "0 of 0".
		#expect(none.approvalsSatisfied == nil)

		#expect(!ApprovalStatus(decision: .approved).requiresNoApprovals)
		#expect(!ApprovalStatus(decision: .approved, approvalsRequired: 1).requiresNoApprovals)
	}
}

@Suite("GitLab avatar URL")
struct GitLabAvatarURLTests {
	@Test("Prefixes instance-relative paths")
	func relativePath() {
		#expect(
			GitLabAvatarURL.absolute("/uploads/-/system/user/avatar/1/avatar.png")
				== "https://gitlab.com/uploads/-/system/user/avatar/1/avatar.png"
		)
	}

	@Test("Leaves absolute URLs alone")
	func absoluteURL() {
		#expect(
			GitLabAvatarURL.absolute("https://secure.gravatar.com/avatar/abc")
				== "https://secure.gravatar.com/avatar/abc"
		)
	}

	@Test("Maps missing and empty to nil")
	func missing() {
		#expect(GitLabAvatarURL.absolute(nil) == nil)
		#expect(GitLabAvatarURL.absolute("") == nil)
	}
}
