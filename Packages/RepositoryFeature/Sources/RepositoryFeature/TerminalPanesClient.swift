import ComposableArchitecture
import Foundation
import SimulatorFeature
import TerminalFeature

extension TerminalViewStore {
	/// The app's panes. One for the process rather than one per window's view state, so reducers
	/// reach the panes through `TerminalPanesClient` and the views only draw them.
	///
	/// Every pane's shell is told where the simulator MCP server listens and which session it is,
	/// so a `claude` started in it reaches the pane beside it (`ClaudeCodeRegistration`) and acts
	/// on its repository's device.
	static let shared = TerminalViewStore(additionalEnvironment: { session in
		SimulatorMCPServer.shared.terminalEnvironment(sessionId: session.id, repositoryPath: session.repositoryPath)
	})
}

/// What reducers ask of the terminal panes, which live outside the state (`TerminalViewStore`):
/// a session is a value, its pane a view with a shell behind it.
@DependencyClient
struct TerminalPanesClient: Sendable {
	/// Hangs up the sessions' shells and drops their panes. A session with no pane is skipped.
	var kill: @Sendable (_ sessionIds: [UUID]) async -> Void
	/// Hangs up every shell, now: for a window that is closing, where an effect would run too
	/// late or not at all. Main actor only.
	var killAll: @Sendable () -> Void
	/// Types Ctrl-C into the session.
	var interrupt: @Sendable (_ sessionId: UUID) async -> Void
	/// Where the session's shell is now, or nil when it has no pane or its shell has exited.
	var currentDirectory: @Sendable (_ sessionId: UUID) async -> String? = { _ in nil }
	/// What each pane is doing, by session, read now: for the tabs saved as the app quits, when
	/// an effect would not get to run. Main actor only.
	var snapshots: @Sendable () -> [UUID: TerminalPaneSnapshot] = { [:] }
	/// Sends a find command to the session's pane.
	var find: @Sendable (_ command: TerminalFindCommand, _ sessionId: UUID) async -> Void
}

extension TerminalPanesClient: DependencyKey {
	static let liveValue = Self(
		kill: { sessionIds in
			await MainActor.run {
				for sessionId in sessionIds {
					TerminalViewStore.shared.killSession(sessionId: sessionId)
				}
			}
		},
		killAll: {
			MainActor.assumeIsolated {
				TerminalViewStore.shared.killAllSessions()
			}
		},
		interrupt: { sessionId in
			await TerminalViewStore.shared.interrupt(sessionId: sessionId)
		},
		currentDirectory: { sessionId in
			await TerminalViewStore.shared.currentDirectory(sessionId: sessionId)
		},
		snapshots: {
			MainActor.assumeIsolated {
				TerminalViewStore.shared.paneSnapshots()
			}
		},
		find: { command, sessionId in
			await TerminalViewStore.shared.performFind(command, sessionId: sessionId)
		}
	)

	static let testValue = Self()
}
