import AppKit
import Foundation
import Observation

@MainActor
@Observable
public final class TerminalViewStore {
	private var views: [UUID: ClaudeAwareTerminalView] = [:]

	public init() {}

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
			executable: "/bin/zsh",
			args: ["-l"],
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
			view.processDelegate = nil // prevent spurious .failed callback
			view.removeFromSuperview() // remove from NSView container
		}
		views.removeValue(forKey: sessionId)
		// Process gets SIGHUP when PTY closes on deallocation
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
