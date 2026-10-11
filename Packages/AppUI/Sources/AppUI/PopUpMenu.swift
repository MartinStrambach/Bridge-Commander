import AppKit
import SwiftUI

// MARK: - Entries

/// One entry of a `PopUpMenuButton`'s menu. Written in a `@PopUpMenuBuilder` block, where a
/// `PopUpMenuAction` stands for itself.
public enum PopUpMenuEntry {
	case action(PopUpMenuAction)
	/// A titled group of entries (a section header in the menu).
	case section(String, [PopUpMenuEntry])
	case submenu(title: String, systemImage: String?, [PopUpMenuEntry])
	/// The system's Share submenu (Messages, Mail, AirDrop…) for `text`.
	case share(title: String, text: String)
	case divider

	public static func section(_ title: String, @PopUpMenuBuilder entries: () -> [PopUpMenuEntry]) -> Self {
		.section(title, entries())
	}

	public static func submenu(
		_ title: String,
		systemImage: String? = nil,
		@PopUpMenuBuilder entries: () -> [PopUpMenuEntry]
	) -> Self {
		.submenu(title: title, systemImage: systemImage, entries())
	}
}

/// A menu item that runs `action` when chosen — the menu's `Button`.
public struct PopUpMenuAction {
	public let title: String
	public let systemImage: String?
	public let isDestructive: Bool
	public let isEnabled: Bool
	/// The item's tooltip.
	public let help: String?
	public let action: @MainActor () -> Void

	public init(
		_ title: String,
		systemImage: String? = nil,
		isDestructive: Bool = false,
		isEnabled: Bool = true,
		help: String? = nil,
		action: @escaping @MainActor () -> Void
	) {
		self.title = title
		self.systemImage = systemImage
		self.isDestructive = isDestructive
		self.isEnabled = isEnabled
		self.help = help
		self.action = action
	}
}

/// Builds `[PopUpMenuEntry]` with `if`, `if`/`else` and `for`, like a `@ViewBuilder` menu.
@resultBuilder
public enum PopUpMenuBuilder {
	public static func buildExpression(_ entry: PopUpMenuEntry) -> [PopUpMenuEntry] {
		[entry]
	}

	public static func buildExpression(_ action: PopUpMenuAction) -> [PopUpMenuEntry] {
		[.action(action)]
	}

	public static func buildExpression(_ entries: [PopUpMenuEntry]) -> [PopUpMenuEntry] {
		entries
	}

	public static func buildBlock(_ parts: [PopUpMenuEntry]...) -> [PopUpMenuEntry] {
		parts.flatMap(\.self)
	}

	public static func buildOptional(_ entries: [PopUpMenuEntry]?) -> [PopUpMenuEntry] {
		entries ?? []
	}

	public static func buildEither(first entries: [PopUpMenuEntry]) -> [PopUpMenuEntry] {
		entries
	}

	public static func buildEither(second entries: [PopUpMenuEntry]) -> [PopUpMenuEntry] {
		entries
	}

	public static func buildArray(_ parts: [[PopUpMenuEntry]]) -> [PopUpMenuEntry] {
		parts.flatMap(\.self)
	}
}

// MARK: - Button

/// A button opening an `NSMenu` built from `entries` when pressed — by default a menu's title
/// with a chevron.
///
/// Stands in for a SwiftUI `Menu` in the repository rows. A `Menu` is an `NSPopUpButton` built,
/// with all of its items, along with the view; the list rebuilds a row each time it scrolls into
/// view, and the menus were a fifth of the scrolling cost (see RepositoryFeature's README). This
/// one is a plain button until it is pressed, and `entries` is called only then, so the menu
/// always reflects the current state.
public struct PopUpMenuButton<Label: View>: View {
	private let label: Label
	private let entries: @MainActor () -> [PopUpMenuEntry]

	/// The menu being shown.
	@State
	private var openMenu: NSMenu?
	@State
	private var isHovered = false

	public init(
		@PopUpMenuBuilder entries: @escaping @MainActor () -> [PopUpMenuEntry],
		@ViewBuilder label: () -> Label
	) {
		self.label = label()
		self.entries = entries
	}

	public var body: some View {
		Button {
			openMenu = NSMenu(entries: entries())
		} label: {
			label
				.padding(.horizontal, 5)
				.padding(.vertical, 2)
				.background(
					Color.primary.opacity(isHovered || openMenu != nil ? 0.08 : 0),
					in: RoundedRectangle(cornerRadius: 5, style: .continuous)
				)
				.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.onHover { isHovered = $0 }
		// Dropped from the button's bottom edge, as a pull-down's menu is. `popUp` runs the menu's
		// tracking loop and returns once it closes.
		.appKitPresentation(item: $openMenu) { menu, anchor, ended in
			menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchor.isFlipped ? anchor.bounds.maxY + 4 : -4), in: anchor)
			ended()
		}
		.accessibilityHint("Shows a menu")
	}
}

public extension PopUpMenuButton where Label == PopUpMenuTitle {
	init(_ title: String, @PopUpMenuBuilder entries: @escaping @MainActor () -> [PopUpMenuEntry]) {
		self.init(entries: entries) {
			PopUpMenuTitle(title: title)
		}
	}
}

/// A menu's title with a chevron, as a pull-down button draws it.
public struct PopUpMenuTitle: View {
	let title: String

	public var body: some View {
		HStack(spacing: 3) {
			Text(title)
				.scaledFont(size: 12)
			Image(systemName: "chevron.down")
				.scaledFont(size: 8, weight: .bold)
				.foregroundStyle(.secondary)
		}
	}
}

// MARK: - NSMenu

extension NSMenu {
	/// A menu holding `entries`; an entry's action runs when it is chosen.
	convenience init(entries: [PopUpMenuEntry]) {
		self.init()
		autoenablesItems = false
		addItems(for: entries)
	}

	private func addItems(for entries: [PopUpMenuEntry]) {
		for entry in entries {
			switch entry {
			case let .action(action):
				addItem(PopUpMenuItem(action))

			case let .section(title, entries):
				if !items.isEmpty {
					addItem(.separator())
				}
				addItem(.sectionHeader(title: title))
				addItems(for: entries)

			case let .submenu(title, systemImage, entries):
				let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
				item.setSymbol(systemImage)
				item.submenu = NSMenu(entries: entries)
				addItem(item)

			case let .share(title, text):
				let picker = NSSharingServicePicker(items: [text])
				let item = picker.standardShareMenuItem
				item.title = title
				// The item does not keep its picker, whose services the submenu's items run.
				item.representedObject = picker
				addItem(item)

			case .divider:
				addItem(.separator())
			}
		}
	}
}

private extension NSMenuItem {
	/// Shows the SF Symbol `name` beside the title. macOS 27 hides menu item images unless asked
	/// to show them, as it does a `Label`'s icon in a SwiftUI `Menu` without `.titleAndIcon`.
	func setSymbol(_ name: String?) {
		image = name.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
		if #available(macOS 27.0, *), image != nil {
			preferredImageVisibility = .visible
		}
	}
}

/// A menu item that runs its entry's action.
private final class PopUpMenuItem: NSMenuItem {
	private let handler: @MainActor () -> Void

	init(_ entry: PopUpMenuAction) {
		handler = entry.action
		super.init(title: entry.title, action: #selector(run), keyEquivalent: "")
		target = self
		isEnabled = entry.isEnabled
		toolTip = entry.help
		setSymbol(entry.systemImage)
		if entry.isDestructive, entry.isEnabled {
			attributedTitle = NSAttributedString(
				string: entry.title,
				attributes: [.foregroundColor: NSColor.systemRed, .font: NSFont.menuFont(ofSize: 0)]
			)
		}
	}

	@available(*, unavailable)
	required init(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	/// AppKit sends menu actions on the main thread.
	@objc
	@MainActor
	private func run() {
		handler()
	}
}
