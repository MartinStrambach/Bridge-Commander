import AppKit
import Foundation
import SwiftTerm

/// Not `@Observable`: no view reads anything off it, and `updateNSView` both reads and writes it,
/// where an observed write makes SwiftUI update the same views again.
@MainActor
public final class TerminalViewStore {
	private var views: [UUID: TerminalPaneView] = [:]
	/// Each pane's process delegate, which SwiftTerm holds only weakly. Kept here, for as long as
	/// the pane, rather than by the terminal panel: the panel can close while its panes run on, and
	/// a pane whose delegate went with the panel reported neither its title nor its shell's exit
	/// again, even once the panel reopened. A pane also moves between the containers of a split
	/// panel, which come and go with the split.
	private var processDelegates: [UUID: TerminalProcessDelegate] = [:]

	/// The terminals on screen, left to right, as the first slot's container last heard it. The
	/// one copy every container goes by — see `TerminalContainerRepresentable.updateNSView`.
	var shownSessionIds: [UUID] = []
	private var slotContainers: [Int: WeakContainer] = [:]

	private struct WeakContainer {
		weak var view: NSView?
	}

	func register(container: NSView, slot: Int) {
		slotContainers[slot] = WeakContainer(view: container)
	}

	/// Forgets a container SwiftUI dropped, unless the slot has a newer one already.
	func unregister(container: NSView, slot: Int) {
		if slotContainers[slot]?.view === container {
			slotContainers[slot] = nil
		}
	}

	func container(forSlot slot: Int) -> NSView? {
		slotContainers[slot]?.view
	}

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
	/// pane keeps the colors, image file permission and events it is created with for its whole
	/// life; later calls' are ignored.
	public func view(
		for session: TerminalSession,
		colors: TerminalColors,
		readsImageFiles: Bool = false,
		events: TerminalPaneEvents
	) -> TerminalPaneView {
		if let existing = views[session.id] {
			return existing
		}

		let terminalView = TerminalPaneView(
			repositoryPath: session.repositoryPath,
			sessionId: session.id,
			readsImageFiles: readsImageFiles,
			events: events
		)

		terminalView.apply(colors)

		let sessionId = session.id
		let processDelegate = TerminalProcessDelegate(
			onFailed: { message in events.onStatusChange(sessionId, .failed(message), nil) },
			onTitleChange: { title in events.onTitleChange(sessionId, title) }
		)
		processDelegates[sessionId] = processDelegate
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

		views[session.id] = terminalView

		// Reported on the next turn of the main queue, not here: panes are created from
		// `updateNSView`, and the report changes the state that update is drawing. A pane killed
		// in between has nothing to report, and one whose program reported its own status first
		// keeps that.
		DispatchQueue.main.async { [weak self] in
			if self?.views[sessionId] === terminalView, !terminalView.hasReportedStatus {
				events.onStatusChange(sessionId, .active, nil)
			}
		}

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

	/// Where the session's shell is now, or `nil` when it has no pane or its shell has exited.
	/// Asks the kernel only, unlike `paneSnapshots()`, which also reads Claude's records from disk.
	public func currentDirectory(sessionId: UUID) -> String? {
		views[sessionId]?.currentDirectory
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

	/// Kills every session: the window that showed them is closing.
	public func killAllSessions() {
		for id in Array(views.keys) {
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
