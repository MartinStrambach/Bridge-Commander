import Foundation
import SwiftTerm

/// Reports a pane whose shell has exited, and the title its program sets. `LocalProcessTerminalView`
/// holds its process delegate weakly, so whoever creates one has to keep it alive for as long as
/// the pane.
public final class TerminalProcessDelegate: LocalProcessTerminalViewDelegate {
	private let onFailed: @Sendable (String) -> Void
	private let onTitleChange: @Sendable (String?) -> Void

	public init(
		onFailed: @escaping @Sendable (String) -> Void,
		onTitleChange: @escaping @Sendable (String?) -> Void = { _ in }
	) {
		self.onFailed = onFailed
		self.onTitleChange = onTitleChange
	}

	public func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

	/// OSC 0/2 (and a title popped off the stack with `CSI 23 t`), already on the main thread:
	/// SwiftTerm parses on its IO thread and hops the title over. The text is the program's, shown
	/// outside the grid, so it is cleaned the way a status report's is; one that cleans up to
	/// nothing reads as no title.
	public func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
		onTitleChange(TerminalProgramReport.displayText(title, maxLength: Self.maxTitleLength))
	}

	/// Longest title kept, in characters. The tab bar truncates far sooner; this bounds what a
	/// program can put into state and the saved tabs.
	private static let maxTitleLength = 200

	public func processTerminated(source: TerminalView, exitCode: Int32?) {
		let message = "Terminal process exited (code \(exitCode ?? -1))"
		let callback = onFailed
		DispatchQueue.main.async {
			callback(message)
		}
	}

	public func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
}
