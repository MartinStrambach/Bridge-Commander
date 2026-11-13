import AppKit
import Foundation
import SwiftTerm

/// Not `@Observable`: no view reads anything off it, and `updateNSView` both reads and writes it,
/// where an observed write makes SwiftUI update the same views again.
@MainActor
public final class TerminalViewStore {
	private var views: [UUID: ClaudeAwareTerminalView] = [:]

	/// Each pane's process delegate, which `LocalProcessTerminalView` holds only weakly. Kept here,
	/// for as long as the pane, rather than by the view that shows it: a pane moves between the
	/// containers of a split panel, and those come and go with the split.
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

	/// Returns the existing terminal view for a session, or creates and starts a new one.
	/// - Parameter processDelegate: Told when the shell exits. Kept by the store for as long as the
	///   pane; `nil` for one that reports the exit as a `.failed` status through `onStatusChange`.
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
		processDelegate: TerminalProcessDelegate? = nil,
		onStatusChange: @escaping @MainActor (UUID, TerminalSessionStatus) -> Void,
		onNotification: @escaping @MainActor (UUID, TerminalNotification) -> Void,
		onOpenFile: @escaping @MainActor (UUID, TerminalFileLink) -> Void = { _, _ in }
	) -> ClaudeAwareTerminalView {
		if let existing = views[session.id] {
			return existing
		}

		let terminalView = ClaudeAwareTerminalView(
			repositoryPath: session.repositoryPath,
			sessionId: session.id,
			statusSource: statusSource,
			onStatusChange: onStatusChange,
			onNotification: onNotification,
			onOpenFile: onOpenFile
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

		let sessionId = session.id
		let processDelegate = processDelegate ?? TerminalProcessDelegate(
			onFailed: { message in onStatusChange(sessionId, .failed(message)) }
		)
		processDelegates[sessionId] = processDelegate
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

		views[session.id] = terminalView

		// Reported on the next turn of the main queue, not here: panes are created from
		// `updateNSView`, and the report changes the state that update is drawing. A pane killed
		// in between has nothing to report.
		DispatchQueue.main.async { [weak self] in
			if self?.views[sessionId] === terminalView {
				onStatusChange(sessionId, .active)
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
