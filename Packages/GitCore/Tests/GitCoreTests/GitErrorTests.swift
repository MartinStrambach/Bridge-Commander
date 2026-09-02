import Testing
@testable import GitCore

@Suite("GitError")
struct GitErrorTests {
	@Test("discardFailed produces a readable description")
	func discardFailedDescription() {
		let error = GitError.discardFailed("permission denied")
		#expect(error.errorDescription == "Failed to discard changes: permission denied")
	}

	@Test("checkoutFailed produces a readable description")
	func checkoutFailedDescription() {
		let error = GitError.checkoutFailed("dirty tree")
		#expect(error.errorDescription == "Failed to checkout: dirty tree")
	}
}
