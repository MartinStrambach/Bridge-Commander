// BridgeCommander/TerminalMode/TerminalViewStore.swift
import AppKit
import Foundation
import Observation
import SwiftTerm

@MainActor
@Observable
final class TerminalViewStore {
	private var views: [UUID: ClaudeAwareTerminalView] = [:]

	/// Returns the existing terminal view for a session, or creates and starts a new one.
	func view(
		for session: TerminalSession,
		onStatusChange: @escaping @Sendable (UUID, TerminalSessionStatus) -> Void
	) -> ClaudeAwareTerminalView {
		if let existing = views[session.id] {
			return existing
		}

		let terminalView = ClaudeAwareTerminalView(frame: .zero)
		terminalView.repositoryPath = session.repositoryPath
		terminalView.sessionId = session.id
		terminalView.onStatusChange = onStatusChange
		// Default to AltGr mode so European keyboards (e.g. Czech Option+4 = $) work correctly.
		// Users can toggle back to Meta mode with Option+Command+O if needed.
		terminalView.optionAsMetaKey = false

		let rawTheme = UserDefaults.standard.string(forKey: "terminalColorTheme") ?? ""
		let theme = TerminalColorTheme(rawValue: rawTheme) ?? .basicDark
		terminalView.nativeForegroundColor = theme.foregroundColor
		terminalView.nativeBackgroundColor = theme.backgroundColor

		let sessionId = session.id
		terminalView.processDelegate = TerminalProcessDelegate(
			onFailed: { message in onStatusChange(sessionId, .failed(message)) }
		)

		terminalView.startProcess(
			executable: "/bin/zsh",
			args: ["-l"],
			environment: nil,
			execName: nil,
			currentDirectory: session.startingDirectory
		)

		onStatusChange(session.id, .active)

		views[session.id] = terminalView
		return terminalView
	}

	func removeSession(sessionId: UUID) {
		views.removeValue(forKey: sessionId)
	}

	func killSession(sessionId: UUID) {
		if let view = views[sessionId] {
			view.processDelegate = nil // prevent spurious .failed callback
			view.removeFromSuperview() // remove from NSView container
		}
		views.removeValue(forKey: sessionId)
		// Process gets SIGHUP when PTY closes on deallocation
	}

	func killAllSessions(for repositoryPath: String) {
		let sessionIds = views.compactMap { id, view -> UUID? in
			view.repositoryPath == repositoryPath ? id : nil
		}
		for id in sessionIds {
			killSession(sessionId: id)
		}
	}

	func killAll() {
		// Removing references lets ARC release LocalProcessTerminalView instances,
		// whose deinit cleans up the underlying PTY. The OS also reclaims child
		// processes when the app exits.
		views.removeAll()
	}
}

// MARK: - ClaudeAwareTerminalView

/// Subclass of LocalProcessTerminalView that monitors terminal content for the
/// Claude Code waiting-for-input prompt (❯, U+276F) and reports status changes.
final class ClaudeAwareTerminalView: LocalProcessTerminalView {
	private static let claudePromptCharacter: Character = "❯" // U+276F

	var repositoryPath: String = ""
	var sessionId: UUID = .init()
	var onStatusChange: (@Sendable (UUID, TerminalSessionStatus) -> Void)?

	private var currentStatus: TerminalSessionStatus = .active
	private var debounceWorkItem: DispatchWorkItem?

	// MARK: - Data-flow based detection

	/// Called by LocalProcess whenever the child process writes bytes to the terminal.
	/// We use the silence between writes as the signal: if no data arrives for
	/// `idleThreshold` seconds AND the Claude prompt character is visible,
	/// the session is waiting for user input.
	override func dataReceived(slice: ArraySlice<UInt8>) {
		super.dataReceived(slice: slice)
		// Data is flowing → Claude is working, not waiting.
		if currentStatus == .waitingForInput {
			reportStatus(.active)
		}
		scheduleIdleCheck()
	}

	/// Called when the user sends keystrokes to the process.
	override func send(source: TerminalView, data: ArraySlice<UInt8>) {
		super.send(source: source, data: data)
		if currentStatus == .waitingForInput {
			reportStatus(.active)
		}
	}

	private func scheduleIdleCheck() {
		debounceWorkItem?.cancel()
		let workItem = DispatchWorkItem { [weak self] in
			guard let self else {
				return
			}

			checkIfWaiting()
		}
		debounceWorkItem = workItem
		DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: workItem)
	}

	/// After 1.5 s of silence from the process, check whether the Claude prompt
	/// character is visible — if so, Claude is waiting for input.
	private func checkIfWaiting() {
		guard let t = terminal else {
			return
		}

		let buf = t.buffer
		for row in 0 ..< t.rows {
			for col in 0 ..< t.cols {
				if buf.getChar(at: Position(col: col, row: row)).getCharacter() == Self.claudePromptCharacter {
					reportStatus(.waitingForInput)
					return
				}
			}
		}
		// No prompt visible — terminal is idle but not at Claude's input.
		reportStatus(.active)
	}

	private func reportStatus(_ status: TerminalSessionStatus) {
		guard status != currentStatus else {
			return
		}

		currentStatus = status
		onStatusChange?(sessionId, status)
	}
}

// MARK: - TerminalProcessDelegate

final class TerminalProcessDelegate: LocalProcessTerminalViewDelegate {
	private let onFailed: @Sendable (String) -> Void

	init(onFailed: @escaping @Sendable (String) -> Void) {
		self.onFailed = onFailed
	}

	func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

	func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

	func processTerminated(source: TerminalView, exitCode: Int32?) {
		DispatchQueue.main.async {
			self.onFailed("Terminal process exited (code \(exitCode ?? -1))")
		}
	}

	func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
}
