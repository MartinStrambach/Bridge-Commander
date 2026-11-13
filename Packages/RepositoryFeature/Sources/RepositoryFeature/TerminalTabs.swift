import ComposableArchitecture
import Foundation
import TerminalFeature

/// One terminal of the panel and the tabs behind it.
struct TerminalPane: Equatable {
	/// The tab on screen in the pane.
	var shown: UUID
	/// The tabs the pane's bar shows, in bar order, `shown` among them: all of one repository.
	var tabs: [UUID]
}

/// Every terminal the app has open and which of them the panel shows: the one place that knows
/// how tabs and panes behave, and the state of `TerminalWorkspaceReducer`. `RepositoryListReducer`
/// decides *what* to open (which command, in which directory, after asking the user or not) and
/// hands the rest to this.
///
/// A tab is a `TerminalSession`. The panel shows one pane, or up to `maxPanes` side by side.
/// Each pane shows one repository and has tabs of its own, in the order `sessions` has them. Two
/// panes may show the same repository, each with its own tabs; a tab never moves from one pane to
/// another while both are on screen. Every tab of a repository that a pane shows belongs to a
/// pane; the tabs of a repository that is not on screen belong to none, and come with it when it
/// is next shown.
///
/// The panes outlive the panel being hidden (`isPanelVisible`), so showing it again finds the
/// split and the keyboard where they were.
@ObservableState
struct TerminalTabs: Equatable {
	/// How many terminals the panel shows side by side.
	static let maxPanes = 3

	/// Every open tab, each repository's in the order its bars show them. Tabs are added and
	/// removed through the operations below, which keep `panes` in step; a session's own fields
	/// (its status) are written in place.
	var sessions: IdentifiedArrayOf<TerminalSession>
	/// The panes, left to right. Empty until a terminal is first shown, and again once the last
	/// tab has closed.
	private(set) var panes: [TerminalPane]
	/// The pane with the keyboard.
	private(set) var activePaneIndex: Int
	/// Whether the panel is on screen. Never while there is no pane to show.
	private(set) var isPanelVisible: Bool
	/// The tab that was last shown for each repository, so switching away from a repository and
	/// back reopens the tab the user left, not its first tab.
	private(set) var lastActiveSessionByRepo: [String: UUID]
	/// Every tab that has had the keyboard, most recent last, so closing the one on screen goes
	/// back to the one the user was in before it.
	private(set) var recentSessionIds: [UUID]

	init(
		sessions: IdentifiedArrayOf<TerminalSession> = [],
		panes: [TerminalPane] = [],
		activePaneIndex: Int = 0,
		isPanelVisible: Bool = false,
		lastActiveSessionByRepo: [String: UUID] = [:],
		recentSessionIds: [UUID] = []
	) {
		self.sessions = sessions
		self.panes = panes
		self.activePaneIndex = activePaneIndex
		self.isPanelVisible = isPanelVisible && !panes.isEmpty
		self.lastActiveSessionByRepo = lastActiveSessionByRepo
		self.recentSessionIds = recentSessionIds
	}

	// MARK: - Queries

	/// The pane with the keyboard.
	var activePane: TerminalPane? {
		panes.indices.contains(activePaneIndex) ? panes[activePaneIndex] : nil
	}

	/// The terminal with the keyboard.
	var activeSessionId: UUID? {
		activePane?.shown
	}

	var activeSession: TerminalSession? {
		activeSessionId.flatMap { sessions[id: $0] }
	}

	/// The repository of the terminal with the keyboard; the toolbar is its.
	var activeRepositoryPath: String? {
		activeSession?.repositoryPath
	}

	/// The terminals the panes show, left to right.
	var shownSessionIds: [UUID] {
		panes.map(\.shown)
	}

	/// Whether the panel has room for one more pane beside the ones it shows.
	var canSplit: Bool {
		!panes.isEmpty && panes.count < Self.maxPanes
	}

	/// Whether the user can see the terminal right now.
	func isOnScreen(_ sessionId: UUID) -> Bool {
		isPanelVisible && panes.contains { $0.shown == sessionId }
	}

	/// Whether a pane shows one of the repository's terminals.
	func showsRepository(_ path: String) -> Bool {
		panes.contains { repositoryPath(of: $0) == path }
	}

	/// The tabs of the pane at `index`, as its bar shows them.
	func tabs(inPane index: Int) -> [TerminalSession] {
		panes.indices.contains(index) ? panes[index].tabs.compactMap { sessions[id: $0] } : []
	}

	/// The pane a tab belongs to, whether it is the one that pane shows or not. Nil for a tab
	/// of a repository that is not on screen.
	func paneIndex(owning sessionId: UUID) -> Int? {
		panes.firstIndex { $0.tabs.contains(sessionId) }
	}

	/// A repository's tabs, in the order `sessions` has them.
	func tabs(of repositoryPath: String) -> [TerminalSession] {
		sessions.filter { $0.repositoryPath == repositoryPath }
	}

	/// The number the repository's next tab gets: one past the highest it has.
	func nextTabIndex(for repositoryPath: String) -> Int {
		(tabs(of: repositoryPath).map(\.tabIndex).max() ?? 0) + 1
	}

	/// The tab to show when a repository is opened again: the one the user last looked at,
	/// falling back to its first tab (and to nothing when it has none).
	func lastActiveSession(for repositoryPath: String) -> TerminalSession? {
		if
			let rememberedId = lastActiveSessionByRepo[repositoryPath],
			let remembered = sessions[id: rememberedId],
			remembered.repositoryPath == repositoryPath
		{
			return remembered
		}
		return sessions.first { $0.repositoryPath == repositoryPath }
	}

	/// Of `sessions`, the one that most recently had the keyboard — nil when none of them has
	/// (tabs restored from the previous launch, say).
	func mostRecent(among sessions: some Collection<TerminalSession>) -> TerminalSession? {
		for id in recentSessionIds.reversed() {
			if let session = sessions.first(where: { $0.id == id }) {
				return session
			}
		}
		return nil
	}

	private func repositoryPath(of pane: TerminalPane) -> String? {
		sessions[id: pane.shown]?.repositoryPath
	}

	/// The repository's tabs that no pane has, in bar order.
	private func unownedTabIds(of repositoryPath: String) -> [UUID] {
		let owned = Set(panes.flatMap(\.tabs))
		return tabs(of: repositoryPath).map(\.id).filter { !owned.contains($0) }
	}

	// MARK: - The panel

	/// Puts the panel on screen, where it was left. Nothing happens while there is no pane to
	/// show: a terminal has to be shown first.
	mutating func showPanel() {
		isPanelVisible = !panes.isEmpty
	}

	/// Takes the panel off screen. The panes stay as they are and every shell keeps running.
	mutating func hidePanel() {
		isPanelVisible = false
	}

	// MARK: - Opening

	/// Gives a tab the keyboard, in the pane it belongs to. A tab of a repository that is not
	/// on screen takes the active pane, which then shows that repository and its tabs. Does not
	/// put the panel on screen; see `showPanel()`.
	mutating func show(_ session: TerminalSession) {
		guard sessions[id: session.id] != nil else {
			return
		}

		if let index = paneIndex(owning: session.id) {
			panes[index].shown = session.id
			activePaneIndex = index
		}
		else if panes.isEmpty {
			panes = [TerminalPane(shown: session.id, tabs: unownedTabIds(of: session.repositoryPath))]
			activePaneIndex = 0
		}
		else {
			// The active pane turns over to the repository. The tabs it had go to another pane
			// showing their repository, when there is one.
			panes[activePaneIndex] = TerminalPane(shown: session.id, tabs: [])
			panes[activePaneIndex].tabs = unownedTabIds(of: session.repositoryPath)
			rehomeUnownedTabs()
		}
		remember(session)
	}

	/// Adds a tab at the end of the bar without showing it: the active pane's when that shows
	/// the tab's repository, else the first pane's that does.
	mutating func add(_ session: TerminalSession) {
		guard sessions[id: session.id] == nil else {
			return
		}

		sessions.append(session)
		if let index = adoptivePaneIndex(for: session.repositoryPath) {
			panes[index].tabs.append(session.id)
		}
	}

	/// Adds a tab at the end of the active pane's bar and shows it there.
	mutating func open(_ session: TerminalSession) {
		add(session)
		show(session)
	}

	/// Opens a pane to the right of the active one, showing `session`, and gives it the
	/// keyboard. A new tab of a repository already on screen is the new pane's only tab (⌘D);
	/// a repository that was not on screen comes with all of its tabs. A tab that a pane has
	/// already is shown where it is, since tabs do not change pane; with no room for another
	/// pane nothing happens.
	mutating func split(showing session: TerminalSession) {
		if sessions[id: session.id] != nil, paneIndex(owning: session.id) != nil {
			show(session)
			return
		}
		guard canSplit else {
			return
		}

		if sessions[id: session.id] == nil {
			sessions.append(session)
		}
		let index = activePaneIndex + 1
		panes.insert(TerminalPane(shown: session.id, tabs: unownedTabIds(of: session.repositoryPath)), at: index)
		activePaneIndex = index
		remember(session)
	}

	/// The panel as the previous launch left it: `split` when it still makes one — several
	/// panes, the terminal that had the keyboard among them — and otherwise the one pane of that
	/// terminal's repository.
	mutating func restorePanel(split: [TerminalPane], showing session: TerminalSession) {
		var owned: Set<UUID> = []
		var restored: [TerminalPane] = []
		for pane in split.prefix(Self.maxPanes) {
			guard let path = sessions[id: pane.shown]?.repositoryPath, !owned.contains(pane.shown) else {
				continue
			}

			let ids = Set(pane.tabs + [pane.shown])
			let tabs = self.tabs(of: path).map(\.id).filter { ids.contains($0) && !owned.contains($0) }
			owned.formUnion(tabs)
			restored.append(TerminalPane(shown: pane.shown, tabs: tabs))
		}
		if restored.count > 1, let active = restored.firstIndex(where: { $0.shown == session.id }) {
			panes = restored
			activePaneIndex = active
			rehomeUnownedTabs()
			remember(session)
		}
		else {
			panes = []
			show(session)
		}
		showPanel()
	}

	/// Sets the tab each repository was showing when the tabs were saved.
	mutating func restoreCurrentTabs(_ currentTabByRepository: [String: UUID]) {
		lastActiveSessionByRepo = currentTabByRepository
	}

	// MARK: - Moving between panes and tabs

	/// A click in a pane. A report naming a terminal that is not on screen is a late one, from a
	/// pane that has since been replaced, and is ignored.
	mutating func focusPane(_ sessionId: UUID) {
		guard
			let index = panes.firstIndex(where: { $0.shown == sessionId }),
			index != activePaneIndex,
			let session = sessions[id: sessionId]
		else {
			return
		}

		activePaneIndex = index
		remember(session)
	}

	/// The next or previous pane, wrapping around.
	mutating func cyclePane(forward: Bool) {
		guard panes.count > 1 else {
			return
		}

		let next = panes[(activePaneIndex + (forward ? 1 : panes.count - 1)) % panes.count]
		focusPane(next.shown)
	}

	/// The next or previous tab of the active pane, in bar order, wrapping around.
	mutating func cycleTab(forward: Bool) {
		let tabs = tabs(inPane: activePaneIndex)
		guard tabs.count > 1, let current = tabs.firstIndex(where: { $0.id == activeSessionId }) else {
			return
		}

		show(tabs[(current + (forward ? 1 : tabs.count - 1)) % tabs.count])
	}

	/// The dragged tab takes the target's place, pushing the target out of the way. Only a tab
	/// of the same pane can be a target: a bar shows one pane's tabs, and a tab does not change
	/// pane. `sessions` interleaves every repository's tabs, so moving within it reorders just
	/// these tabs relative to each other. The tab keeps its number.
	mutating func moveTab(_ sessionId: UUID, onto targetId: UUID) {
		guard
			sessionId != targetId,
			let pane = paneIndex(owning: sessionId),
			pane == paneIndex(owning: targetId),
			let from = sessions.index(id: sessionId),
			let to = sessions.index(id: targetId)
		else {
			return
		}

		var reordered = Array(sessions)
		reordered.insert(reordered.remove(at: from), at: to)
		sessions = IdentifiedArray(uniqueElements: reordered)
		let tabs = Set(panes[pane].tabs)
		panes[pane].tabs = sessions.ids.filter(tabs.contains)
	}

	// MARK: - Closing

	/// Takes a pane out of the split without closing its tabs: their shells keep running. They
	/// go to another pane showing the same repository when there is one, and are otherwise
	/// there again when the repository is next shown. The last pane cannot be taken away.
	mutating func closePane(_ sessionId: UUID) {
		guard panes.count > 1, let index = panes.firstIndex(where: { $0.shown == sessionId }) else {
			return
		}

		panes.remove(at: index)
		if index < activePaneIndex {
			activePaneIndex -= 1
		}
		else if index == activePaneIndex {
			activePaneIndex = min(index, panes.count - 1)
			if let next = activeSession {
				remember(next)
			}
		}
		rehomeUnownedTabs()
	}

	/// Closes tabs. A pane that showed one of them goes on to the nearest of its own tabs — to
	/// its right in the bar first, then to its left — and with none the pane goes too. When the
	/// last pane loses its last tab, the panel moves to the terminal the user was in most
	/// recently, and with none left it closes.
	mutating func close(_ sessionIds: [UUID]) {
		let closed = sessionIds.compactMap { sessions[id: $0] }
		guard !closed.isEmpty else {
			return
		}

		let closedIds = Set(closed.map(\.id))
		for session in closed {
			sessions.remove(id: session.id)
			forget(session)
			if tabs(of: session.repositoryPath).isEmpty {
				lastActiveSessionByRepo[session.repositoryPath] = nil
			}
		}
		guard !panes.isEmpty else {
			return
		}

		var remaining: [TerminalPane] = []
		var active: Int?
		// Where the keyboard goes when the active pane went with its tab.
		var orphanedIndex = 0
		var didChangeShownTab = false
		for (index, pane) in panes.enumerated() {
			var kept = pane
			kept.tabs.removeAll(where: closedIds.contains)
			if closedIds.contains(pane.shown) {
				didChangeShownTab = true
				let position = pane.tabs.firstIndex(of: pane.shown) ?? 0
				let isOpen = { (id: UUID) in !closedIds.contains(id) }
				let successor = pane.tabs.dropFirst(position + 1).first(where: isOpen)
					?? pane.tabs.prefix(position).last(where: isOpen)
				guard let successor else {
					if index == activePaneIndex {
						orphanedIndex = remaining.count
					}
					continue
				}

				kept.shown = successor
				// The tab the pane now shows is its repository's current one, so opening the
				// repository again goes to it and does not turn the pane to another tab.
				if let path = sessions[id: successor]?.repositoryPath, lastActiveSessionByRepo[path] == nil {
					lastActiveSessionByRepo[path] = successor
				}
			}
			if index == activePaneIndex {
				active = remaining.count
			}
			remaining.append(kept)
		}
		if remaining.isEmpty, let next = mostRecent(among: sessions) ?? sessions.first {
			remaining = [TerminalPane(shown: next.id, tabs: tabs(of: next.repositoryPath).map(\.id))]
			active = 0
		}
		panes = remaining
		guard !panes.isEmpty else {
			activePaneIndex = 0
			isPanelVisible = false
			return
		}

		activePaneIndex = active ?? min(orphanedIndex, panes.count - 1)
		if didChangeShownTab, let next = activeSession {
			remember(next)
		}
	}

	/// Puts a new session where an old one was — a retry, a run started again — in its pane's
	/// bar and, when the old one was on screen, in the pane, with the keyboard if the old one
	/// had it.
	mutating func replace(_ sessionId: UUID, with session: TerminalSession) {
		guard let old = sessions[id: sessionId], let position = sessions.index(id: sessionId) else {
			return
		}

		let hadKeyboard = activeSessionId == sessionId
		sessions.remove(id: sessionId)
		sessions.insert(session, at: position)
		let wasRepositoryCurrentTab = lastActiveSessionByRepo[old.repositoryPath] == sessionId
		forget(old)
		if wasRepositoryCurrentTab {
			lastActiveSessionByRepo[old.repositoryPath] = session.id
		}
		for index in panes.indices {
			panes[index].tabs = panes[index].tabs.map { $0 == sessionId ? session.id : $0 }
			if panes[index].shown == sessionId {
				panes[index].shown = session.id
			}
		}
		if hadKeyboard {
			remember(session)
		}
	}

	// MARK: - Memory and ownership

	/// Notes that `session` has the keyboard: it is its repository's current tab and the most
	/// recent one.
	private mutating func remember(_ session: TerminalSession) {
		lastActiveSessionByRepo[session.repositoryPath] = session.id
		recentSessionIds.removeAll { $0 == session.id }
		recentSessionIds.append(session.id)
	}

	/// Drops a closed tab from the memory so it is never restored.
	private mutating func forget(_ session: TerminalSession) {
		if lastActiveSessionByRepo[session.repositoryPath] == session.id {
			lastActiveSessionByRepo[session.repositoryPath] = nil
		}
		recentSessionIds.removeAll { $0 == session.id }
	}

	/// The pane a repository's tab with no pane goes to: the active one when it shows the
	/// repository, else the first that does.
	private func adoptivePaneIndex(for repositoryPath: String) -> Int? {
		if let activePane, self.repositoryPath(of: activePane) == repositoryPath {
			return activePaneIndex
		}
		return panes.firstIndex { self.repositoryPath(of: $0) == repositoryPath }
	}

	/// Hands the tabs a pane left behind — it closed, or turned over to another repository — to
	/// a pane that still shows their repository. Only the operations that take tabs away from a
	/// pane need this; the others place the tabs they touch themselves.
	private mutating func rehomeUnownedTabs() {
		let owned = Set(panes.flatMap(\.tabs))
		var adopted: [Int: Set<UUID>] = [:]
		for session in sessions where !owned.contains(session.id) {
			if let index = adoptivePaneIndex(for: session.repositoryPath) {
				adopted[index, default: []].insert(session.id)
			}
		}
		for (index, ids) in adopted {
			let tabs = ids.union(panes[index].tabs)
			panes[index].tabs = sessions.ids.filter(tabs.contains)
		}
	}
}
