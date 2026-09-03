import AppKit
import Foundation
import SwiftTerm

/// A terminal pane that reports whether it is waiting for the user at Claude Code's prompt.
///
/// The judgement lives in `ClaudeStatusDetector`. This type owns the pane, forwards the two events
/// the detector listens to, and supplies the screen reads it needs through `PromptScreen`.
public final class ClaudeAwareTerminalView: LocalProcessTerminalView {
	public let repositoryPath: String
	public let sessionId: UUID

	private let onStatusChange: @Sendable (UUID, TerminalSessionStatus) -> Void

	/// Built on first use, since it takes this view as its screen and `self` isn't available until
	/// `super.init` has run.
	private lazy var detector = ClaudeStatusDetector(
		label: repositoryPath,
		screen: self,
		onStatusChange: { [weak self] status in
			guard let self else {
				return
			}

			onStatusChange(sessionId, status)
		}
	)

	public init(
		repositoryPath: String,
		sessionId: UUID,
		onStatusChange: @escaping @Sendable (UUID, TerminalSessionStatus) -> Void
	) {
		self.repositoryPath = repositoryPath
		self.sessionId = sessionId
		self.onStatusChange = onStatusChange
		super.init(frame: .zero)
		registerForDraggedTypes([.fileURL])
	}

	/// Unsupported: a pane is only ever built in code, for the session it belongs to.
	public required init?(coder: NSCoder) {
		nil
	}

	/// A pane that goes away for any reason takes its shell with it. `TerminalViewStore` hangs up
	/// explicitly when it kills a session; this covers the store itself being released, as it is
	/// when the window closes.
	isolated deinit {
		hangUp()
	}

	/// Ends the shell the way closing a terminal window does: it gets SIGHUP, exits, and passes the
	/// signal on to its jobs, so a Claude Code session running in the pane goes down with it.
	///
	/// Dropping the view is not enough on its own. SwiftTerm closes its I/O channel without
	/// stopping the read that is always pending on the pseudo-terminal, so the master side stays
	/// open and no hangup ever reaches the shell; a killed pane left zsh and Claude running until
	/// the app quit. SwiftTerm's own `terminate()` would not do either, since it sends SIGTERM and
	/// interactive zsh ignores that.
	///
	/// Safe to call more than once and after the shell has already exited: `running` goes false
	/// as soon as SwiftTerm reaps the child, and a pid that was never assigned is refused so the
	/// signal can never go to this process's own group.
	public func hangUp() {
		guard let process, process.running, process.shellPid > 0 else {
			return
		}

		kill(process.shellPid, SIGHUP)
	}

	/// Called by LocalProcess whenever the child process writes bytes to the terminal.
	override public func dataReceived(slice: ArraySlice<UInt8>) {
		super.dataReceived(slice: slice)
		detector.outputReceived(slice)
	}

	/// Called when bytes are sent to the child process, whether typed, pasted or dropped.
	override public func send(source: TerminalView, data: ArraySlice<UInt8>) {
		super.send(source: source, data: data)
		detector.inputSent(data)
	}
}
