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

@Suite("GitError.nonFastForwardRejection")
struct GitErrorPushRejectionTests {
	@Test("the one ref git refused as non-fast-forward is named")
	func nonFastForward() {
		let error = GitError.pushFailed("""
		To github.com:owner/repo.git
		 ! [rejected]        feature/login -> feature/login (non-fast-forward)
		error: failed to push some refs to 'github.com:owner/repo.git'
		""")
		#expect(error.nonFastForwardRejection == GitRejectedPush(localBranch: "feature/login", remoteBranch: "feature/login"))
	}

	@Test("a branch pushed under another name keeps both names")
	func renamedUpstream() {
		let error = GitError.pushFailed(" ! [rejected]        local-name -> refs/heads/remote-name (non-fast-forward)")
		#expect(error.nonFastForwardRejection == GitRejectedPush(localBranch: "local-name", remoteBranch: "remote-name"))
	}

	@Test("other push failures name nothing", arguments: [
		GitError.pushFailed(" ! [rejected]        feature -> feature (fetch first)"),
		GitError.pushFailed(" ! [rejected]        feature -> feature (remote ref updated since checkout)"),
		GitError.pushFailed("fatal: The current branch feature has no upstream branch."),
		// push.default=matching: more than one refused ref, so no single branch to offer.
		GitError.pushFailed("""
		 ! [rejected]        feature -> feature (non-fast-forward)
		 ! [rejected]        main -> main (non-fast-forward)
		"""),
		GitError.pullFailed(" ! [rejected]        feature -> feature (non-fast-forward)"),
	])
	func otherFailures(error: GitError) {
		#expect(error.nonFastForwardRejection == nil)
	}
}
