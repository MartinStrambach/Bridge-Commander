import AppKit
import Foundation
import Observation

@MainActor
@Observable
public final class TerminalViewStore {
	private var views: [UUID: ClaudeAwareTerminalView] = [:]

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

	/// Returns the existing terminal view for a session, or creates and starts a new one.
	/// The caller is responsible for creating `processDelegate` and keeping a strong reference
	/// to it (e.g. in an NSViewRepresentable Coordinator).
	/// - Parameter ansiPalette: The 16 ANSI colors to install, or `nil` to keep SwiftTerm's
	///   default palette — which is Terminal.app's own, so an imported profile that defines no
	///   ANSI colors renders the same way Terminal renders it.
	/// - Parameter cursorColor: The caret color, or `nil` to keep SwiftTerm's default. Most
	///   Terminal profiles set no cursor color, so `nil` is the usual case.
	/// - Parameter selectionColor: The selection background, or `nil` to keep SwiftTerm's default.
	/// - Parameter statusSource: What the pane's waiting/active status is based on. Only read when
	///   the pane is created.
	public func view(
		for session: TerminalSession,
		foregroundColor: NSColor,
		backgroundColor: NSColor,
		ansiPalette: [NSColor]? = nil,
		cursorColor: NSColor? = nil,
		selectionColor: NSColor? = nil,
		statusSource: ClaudeStatusSource = .progressAndScreen,
		processDelegate: TerminalProcessDelegate,
		onStatusChange: @escaping @Sendable (UUID, TerminalSessionStatus) -> Void,
		onNotification: @escaping @Sendable (UUID, TerminalNotification) -> Void
	) -> ClaudeAwareTerminalView {
		if let existing = views[session.id] {
			return existing
		}

		let terminalView = ClaudeAwareTerminalView(
			repositoryPath: session.repositoryPath,
			sessionId: session.id,
			statusSource: statusSource,
			onStatusChange: onStatusChange,
			onNotification: onNotification
		)

		// Default to AltGr mode so European keyboards (e.g. Czech Option+4 = $) work correctly.
		// Users can toggle back to Meta mode with Option+Command+O if needed.
		terminalView.optionAsMetaKey = false

		terminalView.nativeForegroundColor = foregroundColor
		terminalView.nativeBackgroundColor = backgroundColor
		// Installed after the fg/bg assignment: SwiftTerm derives the extended 256-color
		// palette from the 16 ANSI colors plus the terminal's own background and foreground.
		if let ansiPalette, let colors = TerminalPaletteMapping.swiftTermColors(from: ansiPalette) {
			terminalView.installColors(colors)
		}
		if let cursorColor {
			terminalView.caretColor = cursorColor
		}
		if let selectionColor {
			terminalView.selectedTextBackgroundColor = selectionColor
			// Not optional to set alongside it: SwiftTerm *replaces* the foreground of every
			// selected cell with `selectedTextForegroundColor`, which defaults to black — fine
			// against its own teal default, unreadable against the dark selection colors most
			// Terminal profiles ship. The theme's own text color is the right stand-in: the
			// profile's author picked a selection color that works behind exactly that text.
			terminalView.selectedTextForegroundColor = foregroundColor
		}
		terminalView.terminal.changeHistorySize(3000)

		terminalView.processDelegate = processDelegate
		terminalView.pendingStartupCommand = session.commandToType

		terminalView.startProcess(
			executable: shellExecutable,
			args: shellArguments,
			environment: TerminalEnvironment.variables(requestingProgress: statusSource.requestsProgress)
				+ additionalEnvironment(session),
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
