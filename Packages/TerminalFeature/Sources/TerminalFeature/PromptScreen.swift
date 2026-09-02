/// What the waiting-state heuristic needs to read off a terminal pane.
///
/// The seam exists so the heuristic can be exercised without a live pseudo-terminal. The screens
/// that have fooled it are the interesting ones, and they are awkward to produce for real while
/// being trivial to write down: a frame caught halfway through a repaint, the tail of a previous
/// frame left below the cursor by a resize, a pane scrolled back into history.
///
/// Main actor isolated because every implementation reads live terminal state, which belongs to the
/// pane that owns it.
@MainActor
protocol PromptScreen: AnyObject {
	/// Rows on the visible screen.
	var rowCount: Int { get }

	/// Zero-based row the cursor sits on, relative to the visible screen.
	var cursorRow: Int { get }

	/// Whether the viewport shows the live screen rather than scrollback.
	var isShowingLiveScreen: Bool { get }

	/// Whether Claude owns the pane, or `nil` when the foreground process can't be identified.
	var isClaudeInForeground: Bool? { get }

	/// Whether `row` draws `scalar` within its leading `columns` cells, or `nil` when the row has
	/// nothing written on it at all.
	///
	/// Blank rows are reported apart from the rest because a walk over the screen budgets its work
	/// in rows that have content: untouched cells can't hold a prompt and cost nothing to skip.
	func row(_ row: Int, drawsScalar scalar: UInt32, withinColumns columns: Int) -> Bool?
}
