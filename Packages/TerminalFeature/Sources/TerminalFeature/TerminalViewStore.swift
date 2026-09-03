import AppKit
import Foundation
import Observation

@MainActor
@Observable
public final class TerminalViewStore {
	private var views: [UUID: ClaudeAwareTerminalView] = [:]

	private let shellExecutable: String
	private let shellArguments: [String]

	/// - Parameters:
	///   - shellExecutable: What each pane runs. The app runs the user's login shell; tests run
	///     something cheaper.
	///   - shellArguments: Arguments for `shellExecutable`.
	public init(shellExecutable: String = "/bin/zsh", shellArguments: [String] = ["-l"]) {
		self.shellExecutable = shellExecutable
		self.shellArguments = shellArguments
	}

	/// Returns the existing terminal view for a session, or creates and starts a new one.
	/// The caller is responsible for creating `processDelegate` and keeping a strong reference
	/// to it (e.g. in an NSViewRepresentable Coordinator).
	public func view(
		for session: TerminalSession,
		foregroundColor: NSColor,
		backgroundColor: NSColor,
		processDelegate: TerminalProcessDelegate,
		onStatusChange: @escaping @Sendable (UUID, TerminalSessionStatus) -> Void
	) -> ClaudeAwareTerminalView {
		if let existing = views[session.id] {
			return existing
		}

		let terminalView = ClaudeAwareTerminalView(
			repositoryPath: session.repositoryPath,
			sessionId: session.id,
			onStatusChange: onStatusChange
		)

		// Default to AltGr mode so European keyboards (e.g. Czech Option+4 = $) work correctly.
		// Users can toggle back to Meta mode with Option+Command+O if needed.
		terminalView.optionAsMetaKey = false

		terminalView.nativeForegroundColor = foregroundColor
		terminalView.nativeBackgroundColor = backgroundColor
		terminalView.allowMouseReporting = false
		terminalView.terminal.changeHistorySize(3000)

		terminalView.processDelegate = processDelegate

		terminalView.startProcess(
			executable: shellExecutable,
			args: shellArguments,
			environment: nil,
			execName: nil,
			currentDirectory: session.startingDirectory
		)

		// Store the view before calling onStatusChange to prevent re-entrancy:
		// onStatusChange triggers a TCA state mutation that can cause updateNSView to fire
		// again synchronously; if views[id] were still nil at that point, a second
		// ClaudeAwareTerminalView would be created for the same session.
		views[session.id] = terminalView

		onStatusChange(session.id, .active)

		return terminalView
	}

	public func killSession(sessionId: UUID) {
		if let view = views[sessionId] {
			view.processDelegate = nil // the shell is about to exit on purpose, not fail
			view.hangUp()
			view.removeFromSuperview()
		}
		views.removeValue(forKey: sessionId)
	}

	/// Kills every session that is not in `sessionIds`.
	///
	/// The reducer owns the list of sessions and can drop one without going through this store,
	/// as it does when a worktree is deleted. The view layer calls this whenever that list
	/// changes, so no pane outlives its session whichever way the session went.
	public func killSessions(notIn sessionIds: Set<UUID>) {
		let stale = views.keys.filter { !sessionIds.contains($0) }
		for id in stale {
			killSession(sessionId: id)
		}
	}

	public func killAllSessions(for repositoryPath: String) {
		let sessionIds = views.compactMap { id, view -> UUID? in
			view.repositoryPath == repositoryPath ? id : nil
		}
		for id in sessionIds {
			killSession(sessionId: id)
		}
	}
}
