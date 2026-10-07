import AppUI
import Foundation
@testable import Settings
import Testing

struct RepositoryRowLayoutTests {
	@Test
	func defaultShowsEveryItemInDeclarationOrder() {
		let layout = RepositoryRowLayout.default
		#expect(layout.order == RepositoryRowItem.allCases)
		#expect(layout.items(in: .toolButtons, placedIn: .row) == [.androidStudio, .xcode, .claudeCode])
		#expect(layout.items(in: .actions, placedIn: .row) == layout.items(in: .actions))
		#expect(layout.moreMenuItems.isEmpty)
		#expect(!layout.showsMoreMenu)
		#expect(layout.toolButtonSize == .medium)
	}

	@Test
	func hidingRemovesFromRowItemsOnly() {
		var layout = RepositoryRowLayout.default
		layout.setPlacement(.hidden, for: .xcode)
		#expect(layout.items(in: .toolButtons, placedIn: .row) == [.androidStudio, .claudeCode])
		#expect(layout.items(in: .toolButtons) == [.androidStudio, .xcode, .claudeCode])
		#expect(layout.placement(of: .xcode) == .hidden)

		layout.setPlacement(.row, for: .xcode)
		#expect(layout == .default)
	}

	@Test
	func moreMenuListsMenusAndIconsBeforeToolButtonsInOrder() {
		var layout = RepositoryRowLayout.default
		layout.setPlacement(.moreMenu, for: .claudeCode)
		layout.setPlacement(.moreMenu, for: .terminal)
		layout.setPlacement(.moreMenu, for: .gitActions)
		#expect(layout.moreMenuItems == [.gitActions, .terminal, .claudeCode])
		#expect(!layout.items(in: .actions, placedIn: .row).contains(.terminal))

		// Hiding takes the item out of the menu, and back in the row it is in neither.
		layout.setPlacement(.hidden, for: .terminal)
		#expect(layout.moreMenuItems == [.gitActions, .claudeCode])
		layout.setPlacement(.row, for: .gitActions)
		#expect(layout.moreMenuItems == [.claudeCode])
	}

	@Test
	func moreMenuShowsOnlyWhileItHoldsItems() {
		var layout = RepositoryRowLayout.default
		layout.setPlacement(.moreMenu, for: .copyPath)
		#expect(layout.showsMoreMenu)
		#expect(!layout.items(in: .actions, placedIn: .row).contains(.copyPath))

		layout.setPlacement(.hidden, for: .copyPath)
		#expect(!layout.showsMoreMenu)
	}

	@Test
	func movingStaysWithinItsZone() {
		var layout = RepositoryRowLayout.default
		// Claude Code to the front of the tool buttons.
		layout.move(in: .toolButtons, fromOffsets: [2], toOffset: 0)
		#expect(layout.items(in: .toolButtons) == [.claudeCode, .androidStudio, .xcode])
		#expect(layout.items(in: .actions) == RepositoryRowLayout.default.items(in: .actions))

		// The terminal button to the front of the menus and icons.
		let terminalIndex = layout.items(in: .actions).firstIndex(of: .terminal)!
		layout.move(in: .actions, fromOffsets: [terminalIndex], toOffset: 0)
		#expect(layout.items(in: .actions).first == .terminal)
		#expect(layout.items(in: .toolButtons) == [.claudeCode, .androidStudio, .xcode])
		#expect(layout.order.count == RepositoryRowItem.allCases.count)
	}

	@Test
	func roundTripsThroughRawValue() {
		var layout = RepositoryRowLayout.default
		layout.setPlacement(.hidden, for: .share)
		layout.setPlacement(.moreMenu, for: .xcode)
		layout.toolButtonSize = .small
		layout.move(in: .toolButtons, fromOffsets: [0], toOffset: 3)
		#expect(RepositoryRowLayout(rawValue: layout.rawValue) == layout)
	}

	@Test
	func decodingDropsUnknownAndDuplicateItemsAndAppendsMissingOnes() throws {
		let raw = #"{"order":["claudeCode","bogus","claudeCode","terminal"],"hidden":["web","bogus"],"toolButtonSize":"huge"}"#
		let layout = try #require(RepositoryRowLayout(rawValue: raw))
		#expect(layout.order.prefix(2) == [.claudeCode, .terminal])
		#expect(Set(layout.order) == Set(RepositoryRowItem.allCases))
		#expect(layout.order.count == RepositoryRowItem.allCases.count)
		#expect(layout.hidden == [.web])
		#expect(layout.toolButtonSize == .medium)
		#expect(layout.items(in: .toolButtons) == [.claudeCode, .androidStudio, .xcode])
	}

	@Test
	func decodingKeepsHiddenOverMoreMenu() throws {
		let raw = #"{"hidden":["web"],"inMoreMenu":["web","terminal","bogus"]}"#
		let layout = try #require(RepositoryRowLayout(rawValue: raw))
		#expect(layout.placement(of: .web) == .hidden)
		#expect(layout.moreMenuItems == [.terminal])
	}

	@Test
	func layoutWrittenBeforeTheMoreMenuDecodes() throws {
		let raw = #"{"hidden":["web"],"order":[],"toolButtonSize":"small"}"#
		let layout = try #require(RepositoryRowLayout(rawValue: raw))
		#expect(layout.placement(of: .web) == .hidden)
		#expect(layout.moreMenuItems.isEmpty)
	}

	@Test
	func malformedRawValueReadsAsNil() {
		#expect(RepositoryRowLayout(rawValue: "not json") == nil)
	}
}
