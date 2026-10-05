import AppKit
import SwiftTerm

/// A request to SwiftTerm's built-in find bar, the standard Find menu commands.
///
/// SwiftTerm draws its own find bar (search field, previous/next, case/regex/whole-word options)
/// but opens it only from the Edit ▸ Find menu items, which this app has no menu for. Its show
/// and hide functions are private; the public way in is `performFindPanelAction(_:)`, which reads
/// the command off the sender's tag — so each command is sent as a menu item carrying the tag the
/// real menu item would carry.
public enum TerminalFindCommand: Sendable {
	/// Opens the find bar and focuses it, pre-filled with the selection or, failing that, the
	/// system find pasteboard (what ⌘E last put there, in this app or another).
	case show
	/// Selects the next match of the find bar's text, or of the find pasteboard while it is closed.
	case next
	/// Selects the previous match.
	case previous
	/// Puts the selection on the find pasteboard and opens the find bar with it.
	case useSelection

	var panelAction: NSFindPanelAction {
		switch self {
		case .show:
			.showFindPanel
		case .next:
			.next
		case .previous:
			.previous
		case .useSelection:
			.setFindString
		}
	}
}

extension ClaudeAwareTerminalView {
	func performFind(_ command: TerminalFindCommand) {
		let item = NSMenuItem()
		item.tag = Int(command.panelAction.rawValue)
		performFindPanelAction(item)
	}
}
