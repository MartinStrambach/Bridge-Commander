import AppKit
import Foundation
import Observation
import SwiftTerm

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

		let terminalView = ClaudeAwareTerminalView(frame: .zero)
		terminalView.repositoryPath = session.repositoryPath
		terminalView.sessionId = session.id
		terminalView.onStatusChange = onStatusChange
		// Default to AltGr mode so European keyboards (e.g. Czech Option+4 = $) work correctly.
		// Users can toggle back to Meta mode with Option+Command+O if needed.
		terminalView.optionAsMetaKey = false

		terminalView.nativeForegroundColor = foregroundColor
		terminalView.nativeBackgroundColor = backgroundColor
		terminalView.allowMouseReporting = false

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

	public func removeSession(sessionId: UUID) {
		views.removeValue(forKey: sessionId)
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

	public func killAll() {
		// Removing references lets ARC release LocalProcessTerminalView instances,
		// whose deinit cleans up the underlying PTY. The OS also reclaims child
		// processes when the app exits.
		views.removeAll()
	}
}

// MARK: - ClaudeAwareTerminalView

/// Subclass of LocalProcessTerminalView that monitors terminal content for the
/// Claude Code waiting-for-input prompt (❯, U+276F) and reports status changes.
public final class ClaudeAwareTerminalView: LocalProcessTerminalView {
	private static let claudePromptCharacter: Character = "❯" // U+276F

	public var repositoryPath: String = ""
	public var sessionId: UUID = .init()
	public var onStatusChange: (@Sendable (UUID, TerminalSessionStatus) -> Void)?

	private var currentStatus: TerminalSessionStatus = .active
	private var debounceWorkItem: DispatchWorkItem?

	// MARK: - Init

	override public init(frame: NSRect) {
		super.init(frame: frame)
		registerForDraggedTypes([.fileURL])
	}

	public required init?(coder: NSCoder) {
		super.init(coder: coder)
		registerForDraggedTypes([.fileURL])
	}

	// MARK: - Drag & Drop

	override public func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
		sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
			? .copy
			: []
	}

	override public func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
		let pb = sender.draggingPasteboard
		guard
			let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
			!urls.isEmpty
		else {
			return false
		}

		let paths = urls.map(\.path.shellEscaped).joined(separator: " ")
		guard let bytes = paths.data(using: .utf8) else {
			return false
		}

		send(source: self, data: ArraySlice(bytes))
		return true
	}

	// MARK: - Data-flow based detection

	/// Called by LocalProcess whenever the child process writes bytes to the terminal.
	/// We use the silence between writes as the signal: if no data arrives for
	/// `idleThreshold` seconds AND the Claude prompt character is visible,
	/// the session is waiting for user input.
	override public func dataReceived(slice: ArraySlice<UInt8>) {
		super.dataReceived(slice: slice)
		// Data is flowing → Claude is working, not waiting.
		if currentStatus == .waitingForInput {
			reportStatus(.active)
		}
		scheduleIdleCheck()
	}

	/// Called when the user sends keystrokes to the process.
	override public func send(source: TerminalView, data: ArraySlice<UInt8>) {
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

// MARK: - Shell Escaping

private extension String {
	/// Backslash-escapes shell-special characters so the path can be used as-is
	/// at the command line without surrounding quotes.
	/// e.g. `/foo bar` → `/foo\ bar`, `/it's` → `/it\'s`
	var shellEscaped: String {
		let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "/-_.,=@:+"))
		return unicodeScalars.reduce(into: "") { result, scalar in
			if safe.contains(scalar) {
				result.append(Character(scalar))
			}
			else {
				result += "\\\(Character(scalar))"
			}
		}
	}
}

// MARK: - TerminalProcessDelegate

public final class TerminalProcessDelegate: LocalProcessTerminalViewDelegate {
	private let onFailed: @Sendable (String) -> Void

	public init(onFailed: @escaping @Sendable (String) -> Void) {
		self.onFailed = onFailed
	}

	public func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

	public func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

	public func processTerminated(source: TerminalView, exitCode: Int32?) {
		let message = "Terminal process exited (code \(exitCode ?? -1))"
		let callback = onFailed
		DispatchQueue.main.async {
			callback(message)
		}
	}

	public func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
}
