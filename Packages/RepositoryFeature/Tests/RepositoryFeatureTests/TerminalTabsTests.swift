import ComposableArchitecture
import Foundation
import TerminalFeature
import Testing
@testable import RepositoryFeature

// The rules of tabs and panes, on the value that owns them: what the panel shows after a tab is
// opened, split off, closed or replaced, with one terminal on screen and with several.
@Suite("Terminal tabs")
struct TerminalTabsTests {
	private static let alpha = "/repos/alpha"
	private static let beta = "/repos/beta"

	private func session(_ path: String, _ tabIndex: Int = 1) -> TerminalSession {
		TerminalSession(repositoryPath: path, tabIndex: tabIndex)
	}

	/// Tabs with the panel open on `panes`, the first of them at the keyboard.
	private func makeTabs(_ sessions: [TerminalSession], panes: [TerminalSession]) -> TerminalTabs {
		var focus = TerminalFocus()
		focus.activate(panes[0])
		if panes.count > 1 {
			focus.splitSessionIds = panes.map(\.id)
		}
		return TerminalTabs(sessions: IdentifiedArray(uniqueElements: sessions), focus: focus)
	}

	private func paneIds(_ tabs: TerminalTabs) -> [UUID] {
		tabs.panes.map(\.id)
	}

	// MARK: - Splitting

	@Test("splitting puts a new tab in a pane to the right of the active one and focuses it")
	func splitAddsPaneBesideActive() {
		let one = session(Self.alpha, 1)
		let two = session(Self.alpha, 2)
		var tabs = makeTabs([one, two], panes: [one])
		let added = session(Self.alpha, 3)

		tabs.split(showing: added)

		#expect(tabs.sessions.map(\.id) == [one.id, two.id, added.id])
		#expect(paneIds(tabs) == [one.id, added.id])
		#expect(tabs.focus?.activeSessionId == added.id)
	}

	@Test("another repository's terminal goes beside the one on screen and takes the toolbar")
	func splitShowsAnotherRepository() {
		let alpha = session(Self.alpha)
		let beta = session(Self.beta)
		var tabs = makeTabs([alpha, beta], panes: [alpha])

		tabs.split(showing: beta)

		#expect(tabs.sessions.count == 2)
		#expect(paneIds(tabs) == [alpha.id, beta.id])
		#expect(tabs.focus?.activeRepositoryPath == Self.beta)
		#expect(tabs.focus?.lastActiveSessionByRepo == [Self.alpha: alpha.id, Self.beta: beta.id])
	}

	@Test("a new pane opens right of the active one, not at the end")
	func splitInsertsAfterActivePane() {
		let left = session(Self.alpha, 1)
		let right = session(Self.alpha, 2)
		let added = session(Self.beta)
		var tabs = makeTabs([left, right, added], panes: [left, right])

		tabs.split(showing: added)

		#expect(paneIds(tabs) == [left.id, added.id, right.id])
	}

	@Test("the panel shows at most three terminals")
	func splitStopsAtThreePanes() {
		let sessions = (1 ... 3).map { session(Self.alpha, $0) }
		var tabs = makeTabs(sessions, panes: sessions)

		#expect(!tabs.canSplit)
		tabs.split(showing: session(Self.beta))

		#expect(paneIds(tabs) == sessions.prefix(3).map(\.id))
		#expect(tabs.focus?.activeSessionId == sessions[0].id)
	}

	@Test("splitting to a tab already on screen just focuses its pane")
	func splitToVisibleTabFocusesIt() {
		let left = session(Self.alpha, 1)
		let right = session(Self.alpha, 2)
		var tabs = makeTabs([left, right], panes: [left, right])

		tabs.split(showing: right)

		#expect(paneIds(tabs) == [left.id, right.id])
		#expect(tabs.focus?.activeSessionId == right.id)
	}

	// MARK: - Tabs of a pane

	/// alpha's tabs one and two in the left pane, its tab three in the right one, as ⌘D leaves
	/// them, with the keyboard in the right pane.
	private func twoPanesOfAlpha() -> (TerminalTabs, [TerminalSession]) {
		let one = session(Self.alpha, 1)
		let two = session(Self.alpha, 2)
		let three = session(Self.alpha, 3)
		var tabs = makeTabs([one, two], panes: [one])
		tabs.split(showing: three)
		return (tabs, [one, two, three])
	}

	@Test("a pane split off a repository has the new tab alone; the first pane keeps the others")
	func splitGivesNewPaneItsOwnTab() {
		let (tabs, sessions) = twoPanesOfAlpha()

		#expect(tabs.paneTabIds == [[sessions[0].id, sessions[1].id], [sessions[2].id]])
		#expect(tabs.paneSlot(owning: sessions[1].id) == 0)
	}

	@Test("a tab opened in a pane is that pane's")
	func openAddsToActivePane() {
		var (tabs, sessions) = twoPanesOfAlpha()
		let four = session(Self.alpha, 4)

		tabs.open(four)

		#expect(tabs.paneTabIds == [[sessions[0].id, sessions[1].id], [sessions[2].id, four.id]])
		#expect(paneIds(tabs) == [sessions[0].id, four.id])
	}

	@Test("a tab is shown in the pane it belongs to, not in the one with the keyboard")
	func showStaysInOwningPane() {
		var (tabs, sessions) = twoPanesOfAlpha()

		tabs.show(sessions[1])

		#expect(paneIds(tabs) == [sessions[1].id, sessions[2].id])
		#expect(tabs.focus?.activeSessionId == sessions[1].id)
		#expect(tabs.paneTabIds == [[sessions[0].id, sessions[1].id], [sessions[2].id]])
	}

	@Test("a tab that a pane has is not split off into another pane")
	func splitDoesNotMoveTabs() {
		var (tabs, sessions) = twoPanesOfAlpha()

		tabs.split(showing: sessions[1])

		#expect(paneIds(tabs) == [sessions[1].id, sessions[2].id])
		#expect(tabs.paneTabIds == [[sessions[0].id, sessions[1].id], [sessions[2].id]])
	}

	@Test("a tab cannot be dragged into another pane's bar")
	func moveTabStaysInPane() {
		var (tabs, sessions) = twoPanesOfAlpha()

		tabs.moveTab(sessions[2].id, onto: sessions[0].id)

		#expect(tabs.sessions.map(\.id) == sessions.map(\.id))
		#expect(tabs.paneTabIds == [[sessions[0].id, sessions[1].id], [sessions[2].id]])
	}

	@Test("cycling tabs stays in the pane with the keyboard")
	func cycleTabStaysInPane() {
		var (tabs, sessions) = twoPanesOfAlpha()

		tabs.cycleTab(forward: true)
		#expect(tabs.focus?.activeSessionId == sessions[2].id)

		tabs.show(sessions[0])
		tabs.cycleTab(forward: true)
		#expect(tabs.focus?.activeSessionId == sessions[1].id)
		#expect(paneIds(tabs) == [sessions[1].id, sessions[2].id])
	}

	@Test("a pane that moves on to another repository leaves its tabs to the pane showing theirs")
	func changingRepositoryHandsTabsOver() {
		var (tabs, sessions) = twoPanesOfAlpha()
		let beta = session(Self.beta)
		tabs.add(beta)

		tabs.show(beta)

		#expect(paneIds(tabs) == [sessions[0].id, beta.id])
		#expect(tabs.paneTabIds == [sessions.map(\.id), [beta.id]])
	}

	@Test("a pane taken out of the split leaves its tabs to the pane showing their repository")
	func closePaneHandsTabsOver() {
		var (tabs, sessions) = twoPanesOfAlpha()
		let beta = session(Self.beta)
		tabs.split(showing: beta)

		tabs.closePane(sessions[2].id)

		#expect(paneIds(tabs) == [sessions[0].id, beta.id])
		#expect(tabs.paneTabIds == [sessions.map(\.id), [beta.id]])
	}

	@Test("a repository that was not on screen comes into its pane with all of its tabs")
	func splitBringsRepositoryTabs() {
		let alpha = session(Self.alpha)
		let betaOne = session(Self.beta, 1)
		let betaTwo = session(Self.beta, 2)
		var tabs = makeTabs([alpha, betaOne, betaTwo], panes: [alpha])

		tabs.split(showing: betaTwo)

		#expect(paneIds(tabs) == [alpha.id, betaTwo.id])
		#expect(tabs.paneTabIds == [[alpha.id], [betaOne.id, betaTwo.id]])
	}

	@Test("a tab opened in the background goes to a pane showing its repository")
	func addGoesToPaneOfRepository() {
		let alpha = session(Self.alpha)
		let beta = session(Self.beta)
		var tabs = makeTabs([alpha, beta], panes: [alpha, beta])
		let run = session(Self.beta, 2)

		tabs.add(run)

		#expect(paneIds(tabs) == [alpha.id, beta.id])
		#expect(tabs.paneTabIds == [[alpha.id], [beta.id, run.id]])
	}

	@Test("one pane has all of its repository's tabs")
	func singlePaneHasRepositoryTabs() {
		let one = session(Self.alpha, 1)
		let beta = session(Self.beta)
		let two = session(Self.alpha, 2)
		let tabs = makeTabs([one, beta, two], panes: [one])

		#expect(tabs.paneTabIds == [[one.id, two.id]])
		#expect(tabs.paneSlot(owning: beta.id) == nil)
	}

	// MARK: - Showing

	@Test("a tab that is not on screen takes the active pane; the other panes stay")
	func showReplacesActivePane() {
		let left = session(Self.alpha, 1)
		let right = session(Self.beta)
		let other = session(Self.alpha, 2)
		var tabs = makeTabs([left, right, other], panes: [left, right])

		tabs.show(other)

		#expect(paneIds(tabs) == [other.id, right.id])
		#expect(tabs.focus?.activeSessionId == other.id)
	}

	@Test("a tab that is on screen keeps its pane and gets the keyboard")
	func showFocusesVisiblePane() {
		let left = session(Self.alpha)
		let right = session(Self.beta)
		var tabs = makeTabs([left, right], panes: [left, right])

		tabs.show(right)

		#expect(paneIds(tabs) == [left.id, right.id])
		#expect(tabs.focus?.activeRepositoryPath == Self.beta)
	}

	@Test("a click is honoured only for a pane on screen")
	func focusPaneIgnoresHiddenTabs() {
		let left = session(Self.alpha, 1)
		let right = session(Self.beta)
		let hidden = session(Self.alpha, 2)
		var tabs = makeTabs([left, right, hidden], panes: [left, right])

		tabs.focusPane(hidden.id)
		#expect(tabs.focus?.activeSessionId == left.id)

		tabs.focusPane(right.id)
		#expect(tabs.focus?.activeSessionId == right.id)
	}

	@Test("cycling panes wraps in both directions")
	func cyclePaneWraps() {
		let sessions = [session(Self.alpha), session(Self.beta), session("/repos/gamma")]
		var tabs = makeTabs(sessions, panes: sessions)

		tabs.cyclePane(forward: false)
		#expect(tabs.focus?.activeSessionId == sessions[2].id)

		tabs.cyclePane(forward: true)
		#expect(tabs.focus?.activeSessionId == sessions[0].id)
	}

	@Test("cycling tabs stays in the active repository")
	func cycleTabStaysInRepository() {
		let one = session(Self.alpha, 1)
		let beta = session(Self.beta)
		let two = session(Self.alpha, 2)
		var tabs = makeTabs([one, beta, two], panes: [one])

		tabs.cycleTab(forward: true)
		#expect(tabs.focus?.activeSessionId == two.id)

		tabs.cycleTab(forward: true)
		#expect(tabs.focus?.activeSessionId == one.id)
	}

	@Test("a dragged tab takes the target's place among its repository's tabs")
	func moveTabReorders() {
		let one = session(Self.alpha, 1)
		let beta = session(Self.beta)
		let two = session(Self.alpha, 2)
		let three = session(Self.alpha, 3)
		var tabs = makeTabs([one, beta, two, three], panes: [one])

		tabs.moveTab(one.id, onto: three.id)
		#expect(tabs.tabs(of: Self.alpha).map(\.id) == [two.id, three.id, one.id])

		tabs.moveTab(one.id, onto: beta.id)
		#expect(tabs.tabs(of: Self.alpha).map(\.id) == [two.id, three.id, one.id])
	}

	// MARK: - Closing

	@Test("taking a pane out of the split keeps its tab open")
	func closePaneKeepsTab() {
		let left = session(Self.alpha)
		let middle = session(Self.beta)
		let right = session("/repos/gamma")
		var tabs = makeTabs([left, middle, right], panes: [left, middle, right])

		tabs.closePane(left.id)

		#expect(tabs.sessions.count == 3)
		#expect(paneIds(tabs) == [middle.id, right.id])
		#expect(tabs.focus?.activeSessionId == middle.id)

		tabs.closePane(right.id)

		#expect(paneIds(tabs) == [middle.id])
		#expect(tabs.focus?.splitSessionIds == [])
		#expect(tabs.focus?.activeSessionId == middle.id)
	}

	@Test("the only pane cannot be taken away")
	func closePaneNeedsASplit() {
		let only = session(Self.alpha)
		var tabs = makeTabs([only], panes: [only])

		tabs.closePane(only.id)

		#expect(paneIds(tabs) == [only.id])
	}

	@Test("a closed tab's pane goes on to the tab that took its place in the bar")
	func closeShowsNextTabInPane() {
		let one = session(Self.alpha, 1)
		let two = session(Self.alpha, 2)
		let three = session(Self.alpha, 3)
		let beta = session(Self.beta)
		var tabs = makeTabs([one, two, three, beta], panes: [two, beta])

		tabs.close([two.id])

		#expect(paneIds(tabs) == [three.id, beta.id])
		#expect(tabs.focus?.activeSessionId == three.id)
	}

	@Test("a closed tab with no other tab to show takes its pane with it")
	func closeDropsPaneWithoutSuccessor() {
		let alpha = session(Self.alpha)
		let beta = session(Self.beta)
		let gamma = session("/repos/gamma")
		var tabs = makeTabs([alpha, beta, gamma], panes: [alpha, beta, gamma])

		tabs.close([alpha.id])

		#expect(paneIds(tabs) == [beta.id, gamma.id])
		#expect(tabs.focus?.activeSessionId == beta.id)
		#expect(tabs.focus?.activeRepositoryPath == Self.beta)
		#expect(tabs.focus?.lastActiveSessionByRepo[Self.alpha] == nil)
	}

	@Test("a tab shown in another pane is not shown twice")
	func closeDoesNotDuplicatePane() {
		let one = session(Self.alpha, 1)
		let two = session(Self.alpha, 2)
		var tabs = makeTabs([one, two], panes: [one, two])

		tabs.close([one.id])

		#expect(paneIds(tabs) == [two.id])
		#expect(tabs.focus?.splitSessionIds == [])
	}

	@Test("a pane goes on to the nearest of its own tabs, not to another pane's")
	func closeStaysWithinPane() {
		let one = session(Self.alpha, 1)
		let two = session(Self.alpha, 2)
		let three = session(Self.alpha, 3)
		var tabs = makeTabs([one, two, three], panes: [one, two])

		tabs.close([one.id])

		#expect(paneIds(tabs) == [three.id, two.id])
		#expect(tabs.focus?.activeSessionId == three.id)
	}

	@Test("the tab a pane went on to is the one its repository opens on again")
	func closeRemembersSuccessor() {
		let one = session(Self.alpha, 1)
		let two = session(Self.alpha, 2)
		let three = session(Self.alpha, 3)
		let beta = session(Self.beta)
		var tabs = makeTabs([one, two, three, beta], panes: [beta, three])
		tabs.show(three)
		tabs.show(beta)

		tabs.close([three.id])

		#expect(paneIds(tabs) == [beta.id, two.id])
		#expect(tabs.lastActiveSession(for: Self.alpha)?.id == two.id)
	}

	@Test("closing several tabs at once goes on to the first one left after them")
	func closeSeveralPicksSurvivor() {
		let sessions = (1 ... 4).map { session(Self.alpha, $0) }
		var tabs = makeTabs(sessions, panes: [sessions[1]])

		tabs.close([sessions[0].id, sessions[1].id])

		#expect(tabs.focus?.activeSessionId == sessions[2].id)
	}

	@Test("closing a tab in a pane without the keyboard leaves the keyboard where it is")
	func closeInOtherPaneKeepsFocus() {
		let alpha = session(Self.alpha)
		let beta = session(Self.beta)
		var tabs = makeTabs([alpha, beta], panes: [alpha, beta])

		tabs.close([beta.id])

		#expect(paneIds(tabs) == [alpha.id])
		#expect(tabs.focus?.activeSessionId == alpha.id)
	}

	@Test("closing a tab that is off screen changes nothing on screen")
	func closeOffScreenTab() {
		let one = session(Self.alpha, 1)
		let two = session(Self.alpha, 2)
		let beta = session(Self.beta)
		var tabs = makeTabs([one, two, beta], panes: [one, beta])

		tabs.close([two.id])

		#expect(paneIds(tabs) == [one.id, beta.id])
		#expect(tabs.focus?.activeSessionId == one.id)
	}

	@Test("the last pane losing its repository moves to the terminal used before it")
	func closeFallsBackToMostRecent() {
		let alpha = session(Self.alpha)
		let beta = session(Self.beta)
		let gamma = session("/repos/gamma")
		var tabs = makeTabs([alpha, beta, gamma], panes: [gamma])
		tabs.show(alpha)

		tabs.close([alpha.id])

		#expect(tabs.focus?.activeSessionId == gamma.id)
	}

	@Test("closing the last terminal closes the panel")
	func closeLastTerminalClosesPanel() {
		let only = session(Self.alpha)
		var tabs = makeTabs([only], panes: [only])

		tabs.close([only.id])

		#expect(tabs.sessions.isEmpty)
		#expect(tabs.focus == nil)
	}

	@Test("with the panel hidden, closing only drops the sessions")
	func closeWhileHidden() {
		let alpha = session(Self.alpha)
		let beta = session(Self.beta)
		var tabs = TerminalTabs(sessions: [alpha, beta], focus: nil)

		tabs.close([alpha.id])

		#expect(tabs.sessions.map(\.id) == [beta.id])
		#expect(tabs.focus == nil)
	}

	// MARK: - Replacing

	@Test("a replaced tab keeps its place in the bar and its pane")
	func replaceKeepsPlaceAndPane() {
		let left = session(Self.alpha, 1)
		let right = session(Self.alpha, 2)
		var tabs = makeTabs([left, right], panes: [left, right])
		let retried = session(Self.alpha, 2)

		tabs.replace(right.id, with: retried)

		#expect(tabs.sessions.map(\.id) == [left.id, retried.id])
		#expect(paneIds(tabs) == [left.id, retried.id])
		#expect(tabs.focus?.activeSessionId == left.id)
	}

	@Test("replacing a tab that is off screen leaves the screen alone")
	func replaceOffScreen() {
		let shown = session(Self.alpha, 1)
		let run = session(Self.alpha, 2)
		var tabs = makeTabs([shown, run], panes: [shown])

		tabs.replace(run.id, with: session(Self.alpha, 2))

		#expect(paneIds(tabs) == [shown.id])
	}
}
