import AppKit
import SwiftUI

// MARK: - Entries

/// One entry of a pop-up menu, described once and drawn either by AppKit (`PopUpMenuButton`) or
/// by SwiftUI inside another menu (`PopUpMenuContent`). Written in a `@PopUpMenuBuilder` block,
/// where a `PopUpMenuAction` stands for itself.
public enum PopUpMenuEntry {
	case action(PopUpMenuAction)
	/// A titled group of entries (a section header in the menu).
	case section(String, [PopUpMenuEntry])
	case submenu(title: String, systemImage: String?, [PopUpMenuEntry])
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
	public let action: @MainActor () -> Void

	public init(
		_ title: String,
		systemImage: String? = nil,
		isDestructive: Bool = false,
		isEnabled: Bool = true,
		action: @escaping @MainActor () -> Void
	) {
		self.title = title
		self.systemImage = systemImage
		self.isDestructive = isDestructive
		self.isEnabled = isEnabled
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

// MARK: - AppKit

/// A menu's title with a chevron, opening an `NSMenu` built from `entries` when pressed.
///
/// Stands in for a SwiftUI `Menu` in the repository rows. A `Menu` is an `NSPopUpButton` built,
/// with all of its items, along with the view; the list rebuilds a row each time it scrolls into
/// view, and the three menus were a fifth of the scrolling cost (see RepositoryFeature's README).
/// This one is a plain button until it is pressed, and `entries` is called only then, so the menu
/// always reflects the current state.
public struct PopUpMenuButton: View {
	private let title: String
	private let entries: @MainActor () -> [PopUpMenuEntry]

	/// The menu being shown. Its anchor view exists only meanwhile.
	@State
	private var openMenu: NSMenu?
	@State
	private var isHovered = false

	public init(_ title: String, @PopUpMenuBuilder entries: @escaping @MainActor () -> [PopUpMenuEntry]) {
		self.title = title
		self.entries = entries
	}

	public var body: some View {
		Button {
			openMenu = NSMenu(entries: entries())
		} label: {
			HStack(spacing: 3) {
				Text(title)
					.scaledFont(size: 12)
				Image(systemName: "chevron.down")
					.scaledFont(size: 8, weight: .bold)
					.foregroundStyle(.secondary)
			}
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
		.background {
			if let openMenu {
				PopUpMenuAnchor(menu: openMenu) { self.openMenu = nil }
			}
		}
		.accessibilityHint("Shows a menu")
	}
}

/// Sits behind the button while its menu is open, so the menu drops from the button's bottom
/// edge as a pull-down's does.
private struct PopUpMenuAnchor: NSViewRepresentable {
	let menu: NSMenu
	let onClose: () -> Void

	func makeNSView(context: Context) -> PopUpMenuAnchorView {
		PopUpMenuAnchorView()
	}

	func updateNSView(_ view: PopUpMenuAnchorView, context: Context) {
		view.present(menu, onClose: onClose)
	}
}

private final class PopUpMenuAnchorView: NSView {
	private weak var presentedMenu: NSMenu?

	func present(_ menu: NSMenu, onClose: @escaping () -> Void) {
		guard presentedMenu !== menu else {
			return
		}

		presentedMenu = menu
		// After the SwiftUI update that added this view, once it has a frame: `popUp` runs the
		// menu's tracking loop and returns only when the menu closes.
		Task { @MainActor [weak self] in
			guard let self, window != nil else {
				onClose()
				return
			}

			menu.popUp(positioning: nil, at: NSPoint(x: 0, y: isFlipped ? bounds.maxY + 4 : -4), in: self)
			onClose()
		}
	}
}

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
				item.image = systemImage.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
				item.submenu = NSMenu(entries: entries)
				addItem(item)

			case .divider:
				addItem(.separator())
			}
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
		image = entry.systemImage.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
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

// MARK: - SwiftUI

/// `entries` as the content of a SwiftUI `Menu`, for a menu shown as a submenu of another one
/// (the repository row's "⋯" menu).
public struct PopUpMenuContent: View {
	private let entries: [PopUpMenuEntry]

	public init(@PopUpMenuBuilder entries: () -> [PopUpMenuEntry]) {
		self.entries = entries()
	}

	init(_ entries: [PopUpMenuEntry]) {
		self.entries = entries
	}

	public var body: some View {
		// Offsets as ids: the entries are rebuilt whole every time the menu is drawn.
		ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
			switch entry {
			case let .action(action):
				Button(role: action.isDestructive ? .destructive : nil, action: action.action) {
					if let systemImage = action.systemImage {
						Label(action.title, systemImage: systemImage)
					}
					else {
						Text(action.title)
					}
				}
				.disabled(!action.isEnabled)

			case let .section(title, entries):
				Section(title) {
					PopUpMenuContent(entries)
				}

			case let .submenu(title, systemImage, entries):
				Menu {
					PopUpMenuContent(entries)
				} label: {
					if let systemImage {
						Label(title, systemImage: systemImage)
					}
					else {
						Text(title)
					}
				}

			case .divider:
				Divider()
			}
		}
		// macOS 27 no longer draws a menu item's icon for a bare `Label`, and a submenu's content
		// does not inherit the style from around it, so every level asks for it.
		.labelStyle(.titleAndIcon)
	}
}
