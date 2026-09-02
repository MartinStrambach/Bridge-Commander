import Foundation
import SwiftTerm

/// Reports a pane whose shell has exited. `LocalProcessTerminalView` holds its process delegate
/// weakly, so whoever creates one has to keep it alive for as long as the pane.
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
