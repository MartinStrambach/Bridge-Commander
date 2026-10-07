import AppKit

/// Opens the system's Passwords picker for the focused text field, as Edit ▸ AutoFill ▸
/// Passwords… does. The picker inserts one value of the login the user picks into that field:
/// its username or its password, by the field's `textContentType`.
///
/// There is no public API for it, and the app has no associated domain that would make macOS
/// suggest a login by itself. The item macOS adds to the Edit menu is invoked instead, found by
/// its action — titles are localized.
@MainActor
enum HomerPasswordAutoFill {
	private static let passwordsAction = "_handleInsertFromPasswordsCommand:"

	/// Whether the picker was opened. `false` when macOS no longer adds the item, or it is
	/// disabled because no text field is focused.
	@discardableResult
	static func showPicker() -> Bool {
		guard let mainMenu = NSApp.mainMenu, let item = item(in: mainMenu), let menu = item.menu else {
			return false
		}
		menu.update()
		guard item.isEnabled else {
			return false
		}
		menu.performActionForItem(at: menu.index(of: item))
		return true
	}

	private static func item(in menu: NSMenu) -> NSMenuItem? {
		for item in menu.items {
			if let action = item.action, NSStringFromSelector(action) == passwordsAction {
				return item
			}
			if let submenu = item.submenu, let found = Self.item(in: submenu) {
				return found
			}
		}
		return nil
	}
}
