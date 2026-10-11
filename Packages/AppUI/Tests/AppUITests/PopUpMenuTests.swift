import AppKit
import Testing
@testable import AppUI

@MainActor
@Suite("PopUpMenu")
struct PopUpMenuTests {
	@PopUpMenuBuilder
	private func entries(showsFetch: Bool, isMerging: Bool, branches: [String]) -> [PopUpMenuEntry] {
		if showsFetch {
			PopUpMenuAction("Fetch") {}
		}
		if isMerging {
			PopUpMenuAction("Abort Merge", isDestructive: true) {}
		}
		else {
			PopUpMenuAction("Merge") {}
		}
		for branch in branches {
			PopUpMenuAction(branch) {}
		}
	}

	@Test("the builder keeps the entries its conditions and loops reach, in order")
	func builderFollowsControlFlow() {
		#expect(titles(entries(showsFetch: true, isMerging: false, branches: ["a", "b"])) == ["Fetch", "Merge", "a", "b"])
		#expect(titles(entries(showsFetch: false, isMerging: true, branches: [])) == ["Abort Merge"])
	}

	@Test("the menu carries each item's title, icon and enabled state, and runs its action")
	func menuItems() {
		var ran: [String] = []
		let menu = NSMenu(entries: [
			.action(PopUpMenuAction("Push", systemImage: "arrow.up.circle") { ran.append("Push") }),
			.action(PopUpMenuAction("Stash", isEnabled: false) { ran.append("Stash") }),
		])

		#expect(menu.items.map(\.title) == ["Push", "Stash"])
		#expect(menu.items[0].image != nil)
		#expect(menu.items[1].image == nil)
		#expect(menu.items.map(\.isEnabled) == [true, false])
		#expect(menu.autoenablesItems == false)

		// What AppKit does when the item is chosen (`performActionForItem` needs a running app).
		let push = menu.items[0]
		_ = (push.target as? NSObject)?.perform(push.action)
		#expect(ran == ["Push"])
	}

	@Test("a section is a header after a separator, a submenu nests its entries")
	func sectionsAndSubmenus() {
		let menu = NSMenu(entries: [
			.action(PopUpMenuAction("Generate") {}),
			.section("Move to") {
				PopUpMenuAction("Done") {}
			},
			.submenu("Clean") {
				PopUpMenuAction("Everything") {}
				PopUpMenuEntry.divider
				PopUpMenuAction("Binaries") {}
			},
		])

		#expect(menu.items.map(\.title) == ["Generate", "", "Move to", "Done", "Clean"])
		#expect(menu.items[1].isSeparatorItem)
		#expect(menu.items[2].isSectionHeader)
		#expect(menu.items[4].submenu?.items.map(\.isSeparatorItem) == [false, true, false])
	}

	@Test("an item's help becomes its tooltip; a share entry is the system's Share submenu, titled")
	func tooltipsAndShare() {
		let menu = NSMenu(entries: [
			.action(PopUpMenuAction("Lookup Failed", isEnabled: false, help: "403 Forbidden") {}),
			.share(title: "Share Branch", text: "Branch: main"),
		])

		#expect(menu.items[0].toolTip == "403 Forbidden")
		#expect(menu.items[1].title == "Share Branch")
		#expect(menu.items[1].representedObject is NSSharingServicePicker)
	}

	@Test("an item or submenu with an icon asks for it to be shown (macOS 27 hides menu images otherwise)")
	@available(macOS 27.0, *)
	func iconsAreVisible() {
		let menu = NSMenu(entries: [
			.action(PopUpMenuAction("Push", systemImage: "arrow.up.circle") {}),
			.action(PopUpMenuAction("Stash") {}),
			.submenu("Clean", systemImage: "paintbrush") {},
		])
		#expect(menu.items.map(\.preferredImageVisibility) == [.visible, .automatic, .visible])
	}

	@Test("a section at the top of the menu gets no separator above it")
	func leadingSection() {
		let menu = NSMenu(entries: [.section("Move to") { PopUpMenuAction("Done") {} }])
		#expect(menu.items.map(\.title) == ["Move to", "Done"])
	}

	private func titles(_ entries: [PopUpMenuEntry]) -> [String] {
		entries.map { entry in
			if case let .action(action) = entry {
				action.title
			}
			else {
				"?"
			}
		}
	}
}
