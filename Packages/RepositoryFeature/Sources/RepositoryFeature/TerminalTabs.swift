import ComposableArchitecture
import Foundation
import TerminalFeature

/// What the terminal panel has on screen and what it remembers having shown.
struct TerminalFocus: Equatable {
	/// The repository of the terminal with the keyboard; the toolbar and the tab bar are its.
	var activeRepositoryPath: String?
	/// The terminal with the keyboard.
	var activeSessionId: UUID?
	/// The terminals side by side, left to right, while the panel is split: two or three, the
	/// active one among them. Empty while it is not, when the active terminal is the only pane.
	var splitSessionIds: [UUID] = []
	/// The tabs each pane of the split owns, in step with `splitSessionIds`: the tabs its bar
	/// shows, the one on screen among them. A tab belongs to one pane and never changes pane.
	/// `TerminalTabs` keeps it in order; empty while the panel is not split, when the one pane
	/// has all of its repository's tabs.
	var splitTabIds: [[UUID]] = []
	/// The tab that was last shown for each repository, so switching away from a repository and
	/// back reopens the tab the user left, not its first tab.
	var lastActiveSessionByRepo: [String: UUID] = [:]
	/// Every tab that has had the keyboard since the panel opened, most recent last, so closing
	/// the one on screen goes back to the one the user was in before it.
	var recentSessionIds: [UUID] = []

	/// The terminals on screen, left to right.
	var paneSessionIds: [UUID] {
		if splitSessionIds.isEmpty {
			activeSessionId.map { [$0] } ?? []
		}
		else {
			splitSessionIds
		}
	}

	/// Gives `session` the keyboard and remembers it as its repository's current tab. One that is
	/// not on screen takes the active pane's place; one that is keeps its pane.
	mutating func activate(_ session: TerminalSession) {
		if !splitSessionIds.isEmpty, !splitSessionIds.contains(session.id) {
			if let activeSessionId, let slot = splitSessionIds.firstIndex(of: activeSessionId) {
				splitSessionIds[slot] = session.id
			}
			else {
				splitSessionIds = []
			}
		}
		activeRepositoryPath = session.repositoryPath
		activeSessionId = session.id
		lastActiveSessionByRepo[session.repositoryPath] = session.id
		recentSessionIds.removeAll { $0 == session.id }
		recentSessionIds.append(session.id)
	}

	/// Drops a closed tab from the memory so it is never restored.
	mutating func forget(sessionId: UUID, repositoryPath: String) {
		if lastActiveSessionByRepo[repositoryPath] == sessionId {
			lastActiveSessionByRepo[repositoryPath] = nil
		}
		recentSessionIds.removeAll { $0 == sessionId }
	}

	/// Of `sessions`, the one that most recently had the keyboard — nil when none of them has
	/// since the panel opened (tabs restored from the previous launch, say).
	func mostRecent(among sessions: some Collection<TerminalSession>) -> TerminalSession? {
		for id in recentSessionIds.reversed() {
			if let session = sessions.first(where: { $0.id == id }) {
				return session
			}
		}
		return nil
	}
}

/// Every terminal the app has open and which of them the panel shows: the one place that knows
/// how tabs and panes behave. `RepositoryListReducer` decides *what* to open (which command, in
/// which directory, after asking the user or not) and hands the rest to this.
///
/// A tab is a `TerminalSession`. The panel shows one terminal, or up to `maxPanes` side by side.
/// Each pane shows one repository and has tabs of its own, in the order `sessions` has them: all
/// of the repository's while the panel shows one pane, and while it is split the ones the pane
/// owns. Two panes may show the same repository, each with its own tabs; a tab never moves from
/// one pane to another.
struct TerminalTabs: Equatable {
	/// How many terminals the panel shows side by side.
	static let maxPanes = 3

	var sessions: IdentifiedArrayOf<TerminalSession>
	/// Nil while the panel is hidden. Setting it to nil is how an operation that leaves nothing
	/// to show closes the panel.
	var focus: TerminalFocus?

	// MARK: - Queries

	var activeSession: TerminalSession? {
		focus?.activeSessionId.flatMap { sessions[id: $0] }
	}

	/// The terminals on screen, left to right.
	var panes: [TerminalSession] {
		focus?.paneSessionIds.compactMap { sessions[id: $0] } ?? []
	}

	/// Whether the panel has room for one more pane beside the ones it shows.
	var canSplit: Bool {
		activeSession != nil && panes.count < Self.maxPanes
	}

	func isOnScreen(_ sessionId: UUID) -> Bool {
		focus?.paneSessionIds.contains(sessionId) ?? false
	}

	/// The ids of each pane's tabs, pane by pane from the left, in bar order.
	var paneTabIds: [[UUID]] {
		var tabs = self
		tabs.normalize()
		guard let focus = tabs.focus else {
			return []
		}

		return focus.splitSessionIds.isEmpty
			? tabs.panes.map { pane in tabs.tabs(of: pane.repositoryPath).map(\.id) }
			: focus.splitTabIds
	}

	/// The tabs of the pane at `slot`, as its bar shows them.
	func paneTabs(at slot: Int) -> [TerminalSession] {
		let lists = paneTabIds
		return lists.indices.contains(slot) ? lists[slot].compactMap { sessions[id: $0] } : []
	}

	/// The pane a tab belongs to, whether it is the one that pane shows or not. Nil for a tab
	/// of a repository that is not on screen.
	func paneSlot(owning sessionId: UUID) -> Int? {
		paneTabIds.firstIndex { $0.contains(sessionId) }
	}

	/// Whether a repository has a terminal on screen.
	func isOnScreen(repository path: String) -> Bool {
		panes.contains { $0.repositoryPath == path }
	}

	/// Brings `splitTabIds` in step with the split. Each pane keeps the tabs it had that are
	/// still open and still of the repository it shows. A tab of a repository on screen that no
	/// pane has (one opened in the background, or left behind by a pane that closed or moved on
	/// to another repository) goes to the active pane when that shows its repository, else to
	/// the first pane that does.
	private mutating func normalize() {
		guard var focus else {
			return
		}

		let shown = focus.splitSessionIds
		guard shown.count > 1 else {
			focus.splitTabIds = []
			self.focus = focus
			return
		}

		let repositories = shown.map { sessions[id: $0]?.repositoryPath }
		var owner: [UUID: Int] = [:]
		for (slot, id) in shown.enumerated() {
			owner[id] = slot
		}
		if focus.splitTabIds.count == shown.count {
			for (slot, ids) in focus.splitTabIds.enumerated() {
				for id in ids where owner[id] == nil {
					if let path = sessions[id: id]?.repositoryPath, path == repositories[slot] {
						owner[id] = slot
					}
				}
			}
		}
		let activeSlot = focus.activeSessionId.flatMap { shown.firstIndex(of: $0) }
		for session in sessions where owner[session.id] == nil {
			if let activeSlot, repositories[activeSlot] == session.repositoryPath {
				owner[session.id] = activeSlot
			}
			else if let slot = repositories.firstIndex(of: session.repositoryPath) {
				owner[session.id] = slot
			}
		}
		focus.splitTabIds = shown.indices.map { slot in sessions.ids.filter { owner[$0] == slot } }
		self.focus = focus
	}

	/// A repository's tabs, in the order the tab bar shows them.
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
			let rememberedId = focus?.lastActiveSessionByRepo[repositoryPath],
			let remembered = sessions[id: rememberedId],
			remembered.repositoryPath == repositoryPath
		{
			return remembered
		}
		return sessions.first { $0.repositoryPath == repositoryPath }
	}

	// MARK: - Opening

	/// Gives a tab the keyboard, in the pane it belongs to. A tab of a repository that is not
	/// on screen takes the active pane, which then shows that repository and its tabs.
	mutating func show(_ session: TerminalSession) {
		normalize()
		if
			var focus,
			!focus.splitSessionIds.contains(session.id),
			let slot = focus.splitTabIds.firstIndex(where: { $0.contains(session.id) })
		{
			focus.splitSessionIds[slot] = session.id
			self.focus = focus
		}
		focus?.activate(session)
		normalize()
	}

	/// Adds a tab at the end of the bar without showing it.
	mutating func add(_ session: TerminalSession) {
		sessions.append(session)
		normalize()
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
		guard sessions[id: session.id] == nil || paneSlot(owning: session.id) == nil else {
			show(session)
			return
		}
		guard canSplit, var focus, let activeId = focus.activeSessionId else {
			return
		}

		var tabLists = paneTabIds
		var panes = focus.paneSessionIds
		let slot = (panes.firstIndex(of: activeId) ?? panes.count - 1) + 1
		if sessions[id: session.id] == nil {
			sessions.append(session)
		}
		panes.insert(session.id, at: slot)
		tabLists.insert([session.id], at: slot)
		focus.splitSessionIds = panes
		focus.splitTabIds = tabLists
		focus.activate(session)
		self.focus = focus
		normalize()
	}

	// MARK: - Moving between panes and tabs

	/// A click in a pane. A report naming a terminal that is not on screen is a late one, from a
	/// pane that has since been replaced, and is ignored.
	mutating func focusPane(_ sessionId: UUID) {
		guard
			let focus,
			sessionId != focus.activeSessionId,
			focus.paneSessionIds.contains(sessionId),
			let session = sessions[id: sessionId]
		else {
			return
		}

		show(session)
	}

	/// The next or previous pane, wrapping around.
	mutating func cyclePane(forward: Bool) {
		let panes = panes
		guard panes.count > 1, let current = panes.firstIndex(where: { $0.id == focus?.activeSessionId }) else {
			return
		}

		show(panes[(current + (forward ? 1 : panes.count - 1)) % panes.count])
	}

	/// The next or previous tab of the active pane, in bar order, wrapping around.
	mutating func cycleTab(forward: Bool) {
		guard let activeId = focus?.activeSessionId, let slot = focus?.paneSessionIds.firstIndex(of: activeId) else {
			return
		}

		let tabs = paneTabs(at: slot)
		guard tabs.count > 1 else {
			return
		}

		let current = tabs.firstIndex { $0.id == focus?.activeSessionId } ?? 0
		show(tabs[(current + (forward ? 1 : tabs.count - 1)) % tabs.count])
	}

	/// The dragged tab takes the target's place, pushing the target out of the way. Only a tab
	/// of the same repository and the same pane can be a target: a bar shows one pane's tabs,
	/// and a tab does not change pane. `sessions` interleaves every repository's tabs and the
	/// bars filter it, so moving within it reorders just these tabs relative to each other. The
	/// tab keeps its number.
	mutating func moveTab(_ sessionId: UUID, onto targetId: UUID) {
		guard
			sessionId != targetId,
			let dragged = sessions[id: sessionId],
			let target = sessions[id: targetId],
			dragged.repositoryPath == target.repositoryPath,
			paneSlot(owning: sessionId) == paneSlot(owning: targetId),
			let from = sessions.index(id: sessionId),
			let to = sessions.index(id: targetId)
		else {
			return
		}

		var reordered = Array(sessions)
		reordered.insert(reordered.remove(at: from), at: to)
		sessions = IdentifiedArray(uniqueElements: reordered)
	}

	// MARK: - Closing

	/// Takes a pane out of the split without closing its tabs: their shells keep running. They
	/// go to another pane showing the same repository when there is one, and are otherwise
	/// there again when the repository is next shown. The last pane cannot be taken away.
	mutating func closePane(_ sessionId: UUID) {
		normalize()
		guard var focus, let slot = focus.splitSessionIds.firstIndex(of: sessionId) else {
			return
		}

		var panes = focus.splitSessionIds
		panes.remove(at: slot)
		focus.splitTabIds.remove(at: slot)
		focus.splitSessionIds = panes.count > 1 ? panes : []
		if focus.activeSessionId == sessionId, let next = sessions[id: panes[min(slot, panes.count - 1)]] {
			focus.activate(next)
		}
		self.focus = focus
		normalize()
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

		// The bars as they were, to find each closed tab's neighbours once they are all gone.
		let closedIds = Set(closed.map(\.id))
		let barsBefore = paneTabIds
		for session in closed {
			sessions.remove(id: session.id)
			focus?.forget(sessionId: session.id, repositoryPath: session.repositoryPath)
			if tabs(of: session.repositoryPath).isEmpty {
				focus?.lastActiveSessionByRepo[session.repositoryPath] = nil
			}
		}
		guard var focus else {
			return
		}

		let panes = focus.paneSessionIds
		guard panes.contains(where: closedIds.contains) else {
			return
		}

		var remaining: [UUID] = []
		var remainingTabs: [[UUID]] = []
		var active = focus.activeSessionId.flatMap { closedIds.contains($0) ? nil : $0 }
		// Where the keyboard goes when the active pane went with its tab.
		var orphanedSlot = 0
		for (slot, paneId) in panes.enumerated() {
			let bar = barsBefore.indices.contains(slot) ? barsBefore[slot] : [paneId]
			guard closedIds.contains(paneId) else {
				remaining.append(paneId)
				remainingTabs.append(bar)
				continue
			}

			let index = bar.firstIndex(of: paneId) ?? 0
			let isOpen = { (id: UUID) in !closedIds.contains(id) }
			let successor = bar.dropFirst(index + 1).first(where: isOpen) ?? bar.prefix(index).last(where: isOpen)
			if let successor {
				remaining.append(successor)
				remainingTabs.append(bar)
				// The tab the pane now shows is its repository's current one, so opening the
				// repository again goes to it and does not turn the pane to another tab.
				if let path = sessions[id: successor]?.repositoryPath, focus.lastActiveSessionByRepo[path] == nil {
					focus.lastActiveSessionByRepo[path] = successor
				}
			}
			if paneId == focus.activeSessionId {
				active = successor
				orphanedSlot = remaining.count
			}
		}
		if remaining.isEmpty, let next = focus.mostRecent(among: sessions) ?? sessions.first {
			remaining = [next.id]
			remainingTabs = [[next.id]]
		}
		let nextId = active ?? (remaining.isEmpty ? nil : remaining[min(orphanedSlot, remaining.count - 1)])
		guard let next = nextId.flatMap({ sessions[id: $0] }) else {
			self.focus = nil
			return
		}

		focus.splitSessionIds = remaining.count > 1 ? remaining : []
		focus.splitTabIds = remaining.count > 1 ? remainingTabs : []
		focus.activate(next)
		self.focus = focus
		normalize()
	}

	/// Puts a new session where an old one was — a retry, a run started again — in its pane's
	/// bar and, when the old one was on screen, in the pane, with the keyboard if the old one
	/// had it.
	mutating func replace(_ sessionId: UUID, with session: TerminalSession) {
		guard let old = sessions[id: sessionId], let position = sessions.index(id: sessionId) else {
			return
		}

		sessions.remove(id: sessionId)
		sessions.insert(session, at: position)
		guard var focus else {
			return
		}

		let wasRepositoryCurrentTab = focus.lastActiveSessionByRepo[old.repositoryPath] == sessionId
		focus.forget(sessionId: sessionId, repositoryPath: old.repositoryPath)
		if wasRepositoryCurrentTab {
			focus.lastActiveSessionByRepo[old.repositoryPath] = session.id
		}
		if let slot = focus.splitSessionIds.firstIndex(of: sessionId) {
			focus.splitSessionIds[slot] = session.id
		}
		focus.splitTabIds = focus.splitTabIds.map { $0.map { $0 == sessionId ? session.id : $0 } }
		if focus.activeSessionId == sessionId {
			focus.activate(session)
		}
		self.focus = focus
		normalize()
	}
}
