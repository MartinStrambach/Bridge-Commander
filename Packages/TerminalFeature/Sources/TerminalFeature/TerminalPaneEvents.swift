import Foundation

/// What a pane reports to its owner, each with the session it came from. A pane keeps the events
/// it is created with for its whole life. Each defaults to doing nothing, so a caller names only
/// the ones it handles.
public struct TerminalPaneEvents: Sendable {
	/// The pane's status, and the program's report when it turns to waiting. Also reports
	/// `.failed` once the pane's shell exits on its own.
	public var onStatusChange: @Sendable (UUID, TerminalSessionStatus, TerminalProgramReport?) -> Void
	/// A desktop notification the program asked for (OSC 9 or OSC 777).
	public var onNotification: @Sendable (UUID, TerminalNotification) -> Void
	/// The terminal title the pane's program sets, cleaned for display.
	public var onTitleChange: @Sendable (UUID, String?) -> Void
	/// A ⌘-clicked link that names a file.
	public var onOpenFile: @Sendable (UUID, TerminalFileLink) -> Void

	public init(
		onStatusChange: @escaping @Sendable (UUID, TerminalSessionStatus, TerminalProgramReport?) -> Void = { _, _, _ in },
		onNotification: @escaping @Sendable (UUID, TerminalNotification) -> Void = { _, _ in },
		onTitleChange: @escaping @Sendable (UUID, String?) -> Void = { _, _ in },
		onOpenFile: @escaping @Sendable (UUID, TerminalFileLink) -> Void = { _, _ in }
	) {
		self.onStatusChange = onStatusChange
		self.onNotification = onNotification
		self.onTitleChange = onTitleChange
		self.onOpenFile = onOpenFile
	}
}
