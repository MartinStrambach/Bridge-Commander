import AppKit
import Foundation
import Observation
import SwiftTerm

@MainActor
@Observable
public final class TerminalViewStore {
	private var views: [UUID: TerminalPaneView] = [:]
	/// Each pane's process delegate, which SwiftTerm holds only weakly. Kept here, for as long as
	/// the pane, rather than by the terminal panel: the panel can close while its panes run on, and
	/// a pane whose delegate went with the panel reported neither its title nor its shell's exit
	/// again, even once the panel reopened.
	private var processDelegates: [UUID: TerminalProcessDelegate] = [:]

	private let shellExecutable: String
	private let shellArguments: [String]
	private let additionalEnvironment: @MainActor (TerminalSession) -> [String]

	/// - Parameters:
	///   - shellExecutable: What each pane runs. The app runs the user's login shell; tests run
	///     something cheaper.
	///   - shellArguments: Arguments for `shellExecutable`.
	///   - additionalEnvironment: Extra `NAME=value` variables for a session's shell, beyond
	///     `TerminalEnvironment`'s — the simulator MCP server's address and the session's id, which
	///     come from a package this one does not depend on. Given the whole session, so the server
	///     can also note which repository the session belongs to.
	public init(
		shellExecutable: String = "/bin/zsh",
		shellArguments: [String] = ["-l"],
		additionalEnvironment: @escaping @MainActor (TerminalSession) -> [String] = { _ in [] }
	) {
		self.shellExecutable = shellExecutable
		self.shellArguments = shellArguments
		self.additionalEnvironment = additionalEnvironment
	}

	/// Returns the existing terminal view for a session, or creates and starts a new one. A new
	/// pane keeps the colors and events it is created with for its whole life; later calls' are
	/// ignored.
	public func view(
		for session: TerminalSession,
		colors: TerminalColors,
		events: TerminalPaneEvents
	) -> TerminalPaneView {
		if let existing = views[session.id] {
			return existing
		}

		let terminalView = TerminalPaneView(
			repositoryPath: session.repositoryPath,
			sessionId: session.id,
			events: events
		)

		terminalView.apply(colors)

		let sessionId = session.id
		let processDelegate = TerminalProcessDelegate(
			onFailed: { message in events.onStatusChange(sessionId, .failed(message), nil) },
			onTitleChange: { title in events.onTitleChange(sessionId, title) }
		)
		processDelegates[session.id] = processDelegate
		terminalView.processDelegate = processDelegate
		terminalView.pendingStartupCommand = session.commandToType

		terminalView.startProcess(
			executable: shellExecutable,
			args: shellArguments,
			environment: TerminalEnvironment.variables
				+ additionalEnvironment(session),
			execName: nil,
			currentDirectory: session.startingDirectory
		)

		// Store the view before reporting its status to prevent re-entrancy:
		// the report triggers a TCA state mutation that can cause updateNSView to fire
		// again synchronously; if views[id] were still nil at that point, a second
		// TerminalPaneView would be created for the same session.
		views[session.id] = terminalView

		events.onStatusChange(session.id, .active, nil)

		return terminalView
	}

	/// Sends a find command to a session's pane; a session with no pane yet ignores it.
	public func performFind(_ command: TerminalFindCommand, sessionId: UUID) {
		views[sessionId]?.performFind(command)
	}

	/// What each pane is doing now, by session: where its shell is, and the Claude conversation in
	/// its foreground. A session with no pane, or whose shell has exited, is left out.
	public func paneSnapshots() -> [UUID: TerminalPaneSnapshot] {
		views.compactMapValues { view in
			view.currentDirectory.map { directory in
				TerminalPaneSnapshot(directory: directory, claudeSessionId: view.claudeSessionId)
			}
		}
	}

	/// Types Ctrl-C into the session, stopping what runs in its foreground the way the user would.
	public func interrupt(sessionId: UUID) {
		views[sessionId]?.send(txt: "\u{03}")
	}

	public func killSession(sessionId: UUID) {
		if let view = views[sessionId] {
			view.processDelegate = nil // the shell is about to exit on purpose, not fail
			view.stopReportingStatus()
			view.hangUp()
			view.removeFromSuperview()
		}
		views.removeValue(forKey: sessionId)
		processDelegates.removeValue(forKey: sessionId)
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

/// A pane as the app leaves it, for reopening it on the next launch.
public struct TerminalPaneSnapshot: Equatable, Sendable {
	/// Where the pane's shell is.
	public var directory: String
	/// The Claude Code conversation in the pane's foreground, if there is one.
	public var claudeSessionId: String?

	public init(directory: String, claudeSessionId: String? = nil) {
		self.directory = directory
		self.claudeSessionId = claudeSessionId
	}
}
