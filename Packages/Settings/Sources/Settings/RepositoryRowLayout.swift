import AppUI
import Foundation
import SwiftUI

/// One configurable element of a repository row's action bar.
///
/// The worktree create/delete button and a group's remove button are not listed: they always
/// close the row, so neither can be hidden or moved away from the edge. Nor is the "⋯" menu,
/// which appears only once an item is placed in it.
public enum RepositoryRowItem: String, CaseIterable, Identifiable, Sendable {
	case gitActions
	case tuist
	case youTrackMenu
	case copyPath
	case showInFinder
	case pullRequest
	case pipeline
	case approval
	case share
	case ticket
	case web
	case terminal
	case androidStudio
	case xcode
	case claudeCode

	/// The part of the row an item sits in. Items reorder within their zone only: the tool
	/// buttons are several times the size of the rest, and the small items wrap onto two lines
	/// in a narrow row, which a big button in their midst would make twice as tall.
	public enum Zone: CaseIterable, Sendable {
		case actions
		case toolButtons
	}

	public var id: Self { self }

	/// The text-labelled dropdowns, which `RepositoryRowLayout.stacksMenus` can stack vertically.
	public var isMenu: Bool {
		switch self {
		case .gitActions, .tuist, .youTrackMenu: true
		default: false
		}
	}

	public var zone: Zone {
		switch self {
		case .androidStudio, .xcode, .claudeCode: .toolButtons
		default: .actions
		}
	}

	public var title: String {
		switch self {
		case .gitActions: "Git Actions menu"
		case .tuist: "Tuist menu"
		case .youTrackMenu: "YouTrack menu"
		case .copyPath: "Copy path"
		case .showInFinder: "Show in Finder"
		case .pullRequest: "Pull/merge request"
		case .pipeline: "Pipeline status"
		case .approval: "Review approval"
		case .share: "Share branch, ticket and PR"
		case .ticket: "Open YouTrack ticket"
		case .web: "Web preview"
		case .terminal: "External terminal"
		case .androidStudio: "Android Studio"
		case .xcode: "Xcode"
		case .claudeCode: "Claude Code"
		}
	}

	public var systemImage: String {
		switch self {
		case .gitActions: "arrow.triangle.branch"
		case .tuist: "hammer"
		case .youTrackMenu: "list.bullet.rectangle"
		case .copyPath: "doc.on.doc"
		case .showInFinder: "folder"
		case .pullRequest: "arrow.triangle.pull"
		case .pipeline: "checkmark.circle"
		case .approval: "person.crop.circle.badge.checkmark"
		case .share: "square.and.arrow.up"
		case .ticket: "ticket"
		case .web: "globe"
		case .terminal: "terminal"
		case .androidStudio: "apps.iphone"
		case .xcode: "hammer.fill"
		case .claudeCode: "sparkles"
		}
	}
}

/// Where a repository row draws one of its action bar items.
public enum RepositoryRowItemPlacement: String, CaseIterable, Identifiable, Sendable {
	case row
	/// An entry of the row's "⋯" menu, which sits at the end of the menus and icons.
	case moreMenu
	case hidden

	public var id: Self { self }

	public var title: String {
		switch self {
		case .row: "In Row"
		case .moreMenu: "In More Menu"
		case .hidden: "Hidden"
		}
	}
}

/// One position in the row's menus and icons: a single item, or the menus stacked on top of each
/// other.
public enum RepositoryRowSlot: Hashable, Identifiable, Sendable {
	case item(RepositoryRowItem)
	case menuStack([RepositoryRowItem])

	public var id: Self { self }
}

/// Which action bar items a repository row shows, where (in the row or its "⋯" menu), in what
/// order, and how large its tool buttons are. Settings ▸ Repository Rows edits it; the default is
/// the row as it was before the setting, with everything in the row and no "⋯" menu.
///
/// Stored in user defaults as a JSON string. Decoding is forgiving because the value outlives the
/// app version that wrote it: unknown items are dropped, duplicates collapse, and an item added
/// by a later version is appended (in the row) at the end of its zone.
public struct RepositoryRowLayout: Equatable, Sendable {
	/// Every item exactly once. Zones are filtered out of this one list rather than stored apart.
	public private(set) var order: [RepositoryRowItem]
	/// Disjoint from `inMoreMenu`; an item in neither is drawn in the row.
	public private(set) var hidden: Set<RepositoryRowItem>
	public private(set) var inMoreMenu: Set<RepositoryRowItem>
	public var toolButtonSize: ToolButtonSize
	/// Draws the menus placed in the row (`RepositoryRowItem.isMenu`) as one vertical stack, at
	/// the position of the first of them, instead of side by side.
	public var stacksMenus: Bool

	/// Spelled out: as a `RawRepresentable` the type would otherwise pick up the standard
	/// library's `==` that compares raw values, i.e. JSON strings.
	public static func == (lhs: Self, rhs: Self) -> Bool {
		lhs.order == rhs.order
			&& lhs.hidden == rhs.hidden
			&& lhs.inMoreMenu == rhs.inMoreMenu
			&& lhs.toolButtonSize == rhs.toolButtonSize
			&& lhs.stacksMenus == rhs.stacksMenus
	}

	public static let `default` = RepositoryRowLayout(
		order: RepositoryRowItem.allCases,
		hidden: [],
		inMoreMenu: [],
		toolButtonSize: .medium,
		stacksMenus: false
	)

	public init(
		order: [RepositoryRowItem],
		hidden: Set<RepositoryRowItem>,
		inMoreMenu: Set<RepositoryRowItem> = [],
		toolButtonSize: ToolButtonSize,
		stacksMenus: Bool = false
	) {
		var seen = Set<RepositoryRowItem>()
		self.order = (order + RepositoryRowItem.allCases).filter { seen.insert($0).inserted }
		self.hidden = hidden
		// Hidden wins over a contradictory stored value.
		self.inMoreMenu = inMoreMenu.subtracting(hidden)
		self.toolButtonSize = toolButtonSize
		self.stacksMenus = stacksMenus
	}

	/// The zone's items in order, whatever their placement — what the Settings list shows.
	public func items(in zone: RepositoryRowItem.Zone) -> [RepositoryRowItem] {
		order.filter { $0.zone == zone }
	}

	/// The zone's items placed in `placement`, in order.
	public func items(in zone: RepositoryRowItem.Zone, placedIn placement: RepositoryRowItemPlacement) -> [RepositoryRowItem] {
		items(in: zone).filter { self.placement(of: $0) == placement }
	}

	/// The menus and icons the row draws, in order, with the menus gathered into one stack when
	/// `stacksMenus` is on and more than one of them is in the row.
	public var rowSlots: [RepositoryRowSlot] {
		let rowItems = items(in: .actions, placedIn: .row)
		let menus = rowItems.filter(\.isMenu)
		guard stacksMenus, menus.count > 1 else {
			return rowItems.map(RepositoryRowSlot.item)
		}
		return rowItems.compactMap { item in
			if !item.isMenu {
				.item(item)
			}
			else if item == menus.first {
				.menuStack(menus)
			}
			else {
				nil
			}
		}
	}

	/// The items in the "⋯" menu, in order: the menus and icons first, then the tool buttons.
	public var moreMenuItems: [RepositoryRowItem] {
		RepositoryRowItem.Zone.allCases.flatMap { items(in: $0, placedIn: .moreMenu) }
	}

	/// The row draws its "⋯" menu only while an item is placed in it.
	public var showsMoreMenu: Bool {
		!inMoreMenu.isEmpty
	}

	public func placement(of item: RepositoryRowItem) -> RepositoryRowItemPlacement {
		if hidden.contains(item) {
			.hidden
		}
		else if inMoreMenu.contains(item) {
			.moreMenu
		}
		else {
			.row
		}
	}

	public mutating func setPlacement(_ placement: RepositoryRowItemPlacement, for item: RepositoryRowItem) {
		hidden.remove(item)
		inMoreMenu.remove(item)
		switch placement {
		case .row: break
		case .moreMenu: inMoreMenu.insert(item)
		case .hidden: hidden.insert(item)
		}
	}

	/// Moves items the way `List.onMove` reports it, with offsets into `items(in: zone)`.
	public mutating func move(in zone: RepositoryRowItem.Zone, fromOffsets source: IndexSet, toOffset destination: Int) {
		var zoneItems = items(in: zone)
		zoneItems.move(fromOffsets: source, toOffset: destination)
		var reordered = zoneItems.makeIterator()
		// The zone's slots in `order` keep their positions; only which item fills each changes.
		order = order.map { $0.zone == zone ? reordered.next() ?? $0 : $0 }
	}
}

extension RepositoryRowLayout: Codable {
	private enum CodingKeys: String, CodingKey {
		case order
		case hidden
		case inMoreMenu
		case toolButtonSize
		case stacksMenus
	}

	public init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		let order = try container.decodeIfPresent([String].self, forKey: .order) ?? []
		let hidden = try container.decodeIfPresent([String].self, forKey: .hidden) ?? []
		let inMoreMenu = try container.decodeIfPresent([String].self, forKey: .inMoreMenu) ?? []
		let size = try container.decodeIfPresent(String.self, forKey: .toolButtonSize)
		let stacksMenus = try container.decodeIfPresent(Bool.self, forKey: .stacksMenus) ?? false
		self.init(
			order: order.compactMap(RepositoryRowItem.init(rawValue:)),
			hidden: Set(hidden.compactMap(RepositoryRowItem.init(rawValue:))),
			inMoreMenu: Set(inMoreMenu.compactMap(RepositoryRowItem.init(rawValue:))),
			toolButtonSize: size.flatMap(ToolButtonSize.init(rawValue:)) ?? Self.default.toolButtonSize,
			stacksMenus: stacksMenus
		)
	}

	public func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(order.map(\.rawValue), forKey: .order)
		// Sorted, so an unchanged layout always encodes to the same string.
		try container.encode(hidden.map(\.rawValue).sorted(), forKey: .hidden)
		try container.encode(inMoreMenu.map(\.rawValue).sorted(), forKey: .inMoreMenu)
		try container.encode(toolButtonSize.rawValue, forKey: .toolButtonSize)
		try container.encode(stacksMenus, forKey: .stacksMenus)
	}
}
extension RepositoryRowLayout: RawRepresentable {
	public init?(rawValue: String) {
		guard let layout = try? JSONDecoder().decode(Self.self, from: Data(rawValue.utf8)) else {
			return nil
		}
		self = layout
	}

	public var rawValue: String {
		let encoder = JSONEncoder()
		// Stable output, so an unchanged layout is never written back as a "new" value.
		encoder.outputFormatting = .sortedKeys
		guard let data = try? encoder.encode(self) else {
			return ""
		}
		return String(decoding: data, as: UTF8.self)
	}
}
