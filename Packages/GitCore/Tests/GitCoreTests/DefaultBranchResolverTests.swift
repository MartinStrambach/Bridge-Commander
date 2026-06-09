import Testing
@testable import GitCore

@Suite("DefaultBranchResolver")
struct DefaultBranchResolverTests {
	// MARK: - isDefaultBranch

	@Test("empty config matches master and main, case-insensitively")
	func emptyConfigMatchesMasterMain() {
		#expect(DefaultBranchResolver.isDefaultBranch("master", configured: ""))
		#expect(DefaultBranchResolver.isDefaultBranch("MAIN", configured: ""))
		#expect(!DefaultBranchResolver.isDefaultBranch("develop", configured: ""))
		#expect(!DefaultBranchResolver.isDefaultBranch("feature/x", configured: ""))
	}

	@Test("non-empty config matches only the configured branch")
	func configuredMatchesOnlyConfigured() {
		#expect(DefaultBranchResolver.isDefaultBranch("develop", configured: "develop"))
		#expect(DefaultBranchResolver.isDefaultBranch("DEVELOP", configured: "develop"))
		#expect(!DefaultBranchResolver.isDefaultBranch("master", configured: "develop"))
		#expect(!DefaultBranchResolver.isDefaultBranch("main", configured: "develop"))
	}

	// MARK: - resolveBaseBranch

	@Test("configured branch is chosen when present")
	func configuredChosenWhenPresent() {
		let result = DefaultBranchResolver.resolveBaseBranch(
			configured: "develop",
			available: ["main", "develop", "feature/x"]
		)
		#expect(result == "develop")
	}

	@Test("configured branch absent falls back to master then main")
	func fallsBackToMasterThenMain() {
		#expect(DefaultBranchResolver.resolveBaseBranch(configured: "develop", available: ["master", "main"]) == "master")
		#expect(DefaultBranchResolver.resolveBaseBranch(configured: "", available: ["main", "x"]) == "main")
		#expect(DefaultBranchResolver.resolveBaseBranch(configured: "", available: ["feature/x", "y"]) == "feature/x")
	}

	@Test("empty available list returns nil")
	func emptyAvailableReturnsNil() {
		#expect(DefaultBranchResolver.resolveBaseBranch(configured: "master", available: []) == nil)
	}

	@Test("whitespace-only config is treated as empty")
	func whitespaceConfigTreatedAsEmpty() {
		#expect(DefaultBranchResolver.isDefaultBranch("master", configured: "   "))
		#expect(DefaultBranchResolver.resolveBaseBranch(configured: "   ", available: ["master", "main"]) == "master")
	}

	@Test("configured branch matches available case-insensitively and returns the actual name")
	func configuredMatchesCaseInsensitively() {
		#expect(DefaultBranchResolver.resolveBaseBranch(configured: "Develop", available: ["develop", "main"]) == "develop")
	}
}
