import Testing
@testable import GitHosting

@Suite("PullRequestState")
struct PullRequestStateTests {
	@Test("only draft and ready count as open")
	func isOpen() {
		#expect(PullRequestState.draft.isOpen)
		#expect(PullRequestState.ready.isOpen)
		#expect(!PullRequestState.merged.isOpen)
		#expect(!PullRequestState.closed.isOpen)
	}
}
