import Testing
@testable import GitCore

@Suite("GitCheckoutHelper")
struct GitCheckoutHelperTests {
	@Test("git's pathspec complaint is reworded to name the missing branch")
	func pathspecErrorIsReworded() {
		let message = GitCheckoutHelper.describeFailure(
			branch: "main",
			stderr: "error: pathspec 'main' did not match any file(s) known to git"
		)
		#expect(message == "Branch 'main' was not found locally or on origin.")
	}

	@Test("other git errors are passed through verbatim")
	func otherErrorsPassThrough() {
		let stderr = "error: Your local changes to the following files would be overwritten by checkout"
		#expect(GitCheckoutHelper.describeFailure(branch: "main", stderr: stderr) == stderr)
	}

	@Test("empty stderr gets a generic message")
	func emptyStderrGetsGenericMessage() {
		#expect(
			GitCheckoutHelper.describeFailure(branch: "main", stderr: "")
				== "Checkout couldn't be finished. Check the repository state."
		)
	}
}
