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
