import ComposableArchitecture
import Foundation
import TerminalFeature
import Testing
@testable import RepositoryFeature

// A pane reports its Claude status to the session list, which is parent state: the terminal panel
// can be closed while a session keeps running, and the dots in the repository list still have to
// move. The report must therefore not be routed through the panel's child reducer, whose state is
// nil whenever the panel is closed.
@Suite("Repository list terminal session status")
@MainActor
struct RepositoryListTerminalStatusTests {
	@Test("updates the session while the terminal panel is closed")
	func updatesSessionWhilePanelClosed() async {
		let session = TerminalSession(repositoryPath: "/repos/alpha")
		var state = RepositoryListReducer.State()
		state.terminalSessions = [session]
		let store = TestStore(initialState: state) {
			RepositoryListReducer()
		}

		await store.send(.view(.terminalSessionStatusChanged(sessionId: session.id, status: .waitingForInput))) {
			$0.terminalSessions[id: session.id]?.status = .waitingForInput
		}
	}

	@Test("ignores a late report from a session that has already been killed")
	func ignoresReportForKilledSession() async {
		let store = TestStore(initialState: RepositoryListReducer.State()) {
			RepositoryListReducer()
		}

		await store.send(.view(.terminalSessionStatusChanged(sessionId: UUID(), status: .active)))
	}
}
