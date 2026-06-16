import Testing
@testable import GitCore

@Suite("GitError")
struct GitErrorTests {
	@Test("discardFailed produces a readable description")
	func discardFailedDescription() {
		let error = GitError.discardFailed("permission denied")
		#expect(error.errorDescription == "Failed to discard changes: permission denied")
	}
}
