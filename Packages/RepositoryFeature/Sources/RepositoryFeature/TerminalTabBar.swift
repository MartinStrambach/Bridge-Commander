import AppUI
import ComposableArchitecture
import SwiftUI
import TerminalFeature

/// One pane's tabs and the buttons that open another tab in it or another pane beside it. Every
/// pane of a split has its own bar, over its terminal; a panel showing one terminal has one bar.
/// The bar of the first pane also carries the panel's keyboard shortcuts, as hidden buttons, so
/// they are registered once however many panes there are.
struct TerminalTabBar: View {
	let store: StoreOf<TerminalLayoutReducer>
	let sessions: IdentifiedArrayOf<TerminalSession>
	let terminalViewStore: TerminalViewStore
	/// The pane's tabs, in bar order.
	let tabs: [TerminalSession]
	/// The tab the pane shows.
	let shownSessionId: UUID?
	/// Whose terminals the pane shows, named at the head of the bar while the panel is split —
	/// the toolbar names only the repository with the keyboard. Nil while it is not, when the
	/// bar also has no button that takes the pane away.
	var paneTitle: String?
	var hostsShortcuts = true
	let onNewTab: () -> Void
	let onSelectTab: (UUID) -> Void
	let onKillTab: (UUID) -> Void

	/// The tab being dragged, set when its drag starts and read by every other tab's drop
	/// delegate to move it as the pointer passes over them. Local to this bar, so a tab dragged
	/// over another pane's bar moves nothing there: tabs do not change pane.
	@State
	private var draggedTabId: UUID?

	private var activeSessionId: UUID? {
		store.activeSessionId
	}

	/// Whether this bar's pane has the keyboard.
	private var isFocused: Bool {
		shownSessionId != nil && shownSessionId == activeSessionId
	}

	/// Whether the panel has room for another pane.
	private var canSplit: Bool {
		activeSessionId != nil && store.paneSessionIds.count < TerminalTabs.maxPanes
	}

	/// The tabs of the pane with the keyboard, which ⌘1…⌘9 choose among.
	private var activePaneTabs: [TerminalSession] {
		guard let activeSessionId, let slot = store.paneSessionIds.firstIndex(of: activeSessionId) else {
			return []
		}

		return TerminalTabs(sessions: sessions, focus: store.focus).paneTabs(at: slot)
	}

	var body: some View {
		HStack(spacing: 0) {
			if let paneTitle {
				Text(paneTitle)
					.scaledFont(.caption)
					.fontWeight(isFocused ? .semibold : .regular)
					.foregroundStyle(isFocused ? .primary : .secondary)
					.lineLimit(1)
					.truncationMode(.middle)
					.padding(.leading, 8)
					.layoutPriority(1)
			}

			ScrollView(.horizontal, showsIndicators: false) {
				HStack(spacing: 4) {
					ForEach(tabs) { session in
						tabPill(session: session, isShown: session.id == shownSessionId, totalCount: tabs.count)
					}

					Button {
						takeKeyboard()
						onNewTab()
					} label: {
						Image(systemName: "plus")
							.scaledFont(size: 11)
							.padding(.horizontal, 6)
							.padding(.vertical, 4)
							.contentShape(Rectangle())
					}
					.buttonStyle(.borderless)
					.help("New Tab (⌘T)")

					Button {
						takeKeyboard()
						requestSplit()
					} label: {
						Image(systemName: "rectangle.split.2x1")
							.scaledFont(size: 11)
							.padding(.horizontal, 6)
							.padding(.vertical, 4)
							.contentShape(Rectangle())
					}
					.buttonStyle(.borderless)
					.help("Split: a new terminal beside this one (⌘D), up to \(TerminalTabs.maxPanes) side by side")
					.disabled(!canSplit)

					if hostsShortcuts {
						shortcuts
					}
				}
				.padding(.horizontal, 8)
				.padding(.vertical, 4)
			}

			if paneTitle != nil, let shownSessionId {
				Button(action: { store.send(.closePane(sessionId: shownSessionId)) }) {
					Image(systemName: "xmark")
						.scaledFont(size: 9)
						.padding(6)
						.contentShape(Rectangle())
				}
				.buttonStyle(.borderless)
				.help("Remove this pane from the split (its tabs stay open)")
			}
		}
		.background(
			paneTitle != nil && isFocused ? Color.accentColor.opacity(0.08) : Color(NSColor.windowBackgroundColor)
		)
		.contentShape(Rectangle())
		.onTapGesture {
			takeKeyboard()
		}
	}

	/// Gives this bar's pane the keyboard, so what its buttons open lands in it.
	private func takeKeyboard() {
		if let shownSessionId, shownSessionId != activeSessionId {
			store.send(.paneFocused(sessionId: shownSessionId))
		}
	}

	/// The directory is read when the split is asked for, not captured: it is wherever the
	/// active terminal's shell is by then.
	private func requestSplit() {
		let directory = store.activeSessionId.flatMap { terminalViewStore.currentDirectory(sessionId: $0) }
		store.send(.splitRequested(directory: directory))
	}

	// MARK: - Tab Pill

	private func tabPill(session: TerminalSession, isShown: Bool, totalCount: Int) -> some View {
		HStack(spacing: 4) {
			if let runTitle = session.runTitle {
				Label(runTitle, systemImage: "play.fill")
					.labelStyle(.titleAndIcon)
					.scaledFont(.caption)
					.fontWeight(isShown ? .semibold : .regular)
			}
			else {
				Text("Terminal \(session.tabIndex)")
					.scaledFont(.caption)
					.fontWeight(isShown ? .semibold : .regular)
			}

			if paneTitle != nil {
				TerminalStatusDotView(status: session.status)
			}

			if totalCount > 1 {
				Button(action: { onKillTab(session.id) }) {
					Image(systemName: "xmark")
						.scaledFont(size: 8)
						.padding(4)
						.contentShape(Rectangle())
				}
				.buttonStyle(.borderless)
			}
		}
		.padding(.horizontal, 10)
		.padding(.vertical, 6)
		.background(isShown ? (isFocused ? Color.accentColor : Color.secondary).opacity(0.15) : Color.clear)
		.cornerRadius(6)
		.contentShape(Rectangle())
		.onTapGesture {
			onSelectTab(session.id)
		}
		.liveReorderable(
			id: session.id,
			isEnabled: totalCount > 1,
			draggedId: $draggedTabId,
			onMove: { dragged, target in
				store.send(.moveTab(sessionId: dragged, ontoSessionId: target))
			}
		)
	}

	// MARK: - Shortcuts

	/// Every shortcut of the panel. They act on the pane with the keyboard, whichever bar hosts
	/// them.
	@ViewBuilder
	private var shortcuts: some View {
		let repoSessions = sessions.filter { $0.repositoryPath == store.activeRepositoryPath }

		Group {
			Button("", action: onNewTab)
				.keyboardShortcut("t", modifiers: .command)
			Button("", action: requestSplit)
				.keyboardShortcut("d", modifiers: .command)
				.disabled(!canSplit)
		}
		.hidden()

		// Hidden buttons for Cmd+1…Cmd+9 tab switching
		ForEach(Array(activePaneTabs.prefix(9).enumerated()), id: \.element.id) { index, session in
			let key = KeyEquivalent(Character(String(index + 1)))
			Button("") { onSelectTab(session.id) }
				.keyboardShortcut(key, modifiers: .command)
				.hidden()
		}

		cycleTabShortcuts
		cyclePaneShortcuts
		closeTabShortcut(repoSessions: repoSessions)
		refreshShortcut
		zoomShortcuts
		findShortcuts
	}

	/// ⌘W closes the active tab. On the repo's last tab it is registered only while *another*
	/// repository still has terminals running — there the reducer asks whether to close just this
	/// tab or quit the app, since either reading is plausible. With nothing else running the
	/// shortcut is deliberately left unregistered so it falls back to the standard File ▸ Close
	/// and shuts the window — a view-level `keyboardShortcut` wins over the menu item (same as
	/// ⌘A in `RepositoryListView`), so registering it unconditionally would strand the window.
	/// Yielded while a sheet is up: the staging panel and the graph are their own windows to close.
	///
	/// The action deliberately carries no session id and does not go through `onKillTab`: SwiftUI
	/// held on to the closure this button was first laid out with, so a captured id killed the
	/// same, already-removed session on every press after the first. The reducer resolves the
	/// active tab instead, and hangs the shell up via `killSessions(notIn:)` in `RepositoryListView`.
	@ViewBuilder
	private func closeTabShortcut(repoSessions: some Collection<TerminalSession>) -> some View {
		let hasOtherRepoSessions = sessions.contains { $0.repositoryPath != store.activeRepositoryPath }
		if repoSessions.count > 1 || hasOtherRepoSessions,
		   let activeSessionId,
		   repoSessions.contains(where: { $0.id == activeSessionId }),
		   store.stagingDetail == nil,
		   store.gitGraph == nil {
			Button("") { store.send(.closeActiveTabRequested) }
				.keyboardShortcut("w", modifiers: .command)
				.hidden()
		}
	}

	/// ⌃Tab / ⌃⇧Tab cycle through the active pane's tabs, the shortcut Terminal.app uses. The
	/// reducer resolves the active tab when the key fires, for the reason ⌘W documents. Yielded
	/// while a sheet is up for the same reason the zoom shortcuts are.
	@ViewBuilder
	private var cycleTabShortcuts: some View {
		if store.stagingDetail == nil, store.gitGraph == nil {
			Group {
				Button("") { store.send(.cycleTabRequested(forward: true)) }
					.keyboardShortcut(.tab, modifiers: .control)
				Button("") { store.send(.cycleTabRequested(forward: false)) }
					.keyboardShortcut(.tab, modifiers: [.control, .shift])
			}
			.hidden()
		}
	}

	/// ⌘] / ⌘[ move the keyboard between the panes of the split, the shortcuts iTerm uses. The
	/// reducer resolves the active pane when the key fires, for the reason ⌘W documents. Always
	/// registered, deciding at press time whether a sheet is up: a shortcut button inserted and
	/// removed with the sheets can stop being delivered on macOS 27.
	private var cyclePaneShortcuts: some View {
		Group {
			Button("") { cyclePane(forward: true) }
				.keyboardShortcut("]", modifiers: .command)
			Button("") { cyclePane(forward: false) }
				.keyboardShortcut("[", modifiers: .command)
		}
		.hidden()
	}

	private func cyclePane(forward: Bool) {
		if store.stagingDetail == nil, store.gitGraph == nil {
			store.send(.cyclePaneRequested(forward: forward))
		}
	}

	/// ⌘R refreshes only the repo opened in the terminal; the full-list refresh in
	/// `RepositoryListView` hands the shortcut off while the panel is open. The staging sheet and
	/// the commit graph claim ⌘R for their own refresh, so yield it there — a shortcut registered
	/// twice dispatches to either owner at random.
	///
	/// Registered here beside the other hidden shortcuts rather than in the sidebar's
	/// `.background`: on macOS 27 a conditionally inserted shortcut button inside a `.background`
	/// never fires (the unconditional ⌘§ beside it still does), so ⌘R silently did nothing.
	@ViewBuilder
	private var refreshShortcut: some View {
		if store.stagingDetail == nil, store.gitGraph == nil {
			Button("") { store.send(.refreshActiveRepoRequested) }
				.keyboardShortcut("r", modifiers: .command)
				.hidden()
		}
	}

	/// ⌘+ / ⌘− / ⌘0 zoom the terminal font, the shortcuts every terminal emulator uses.
	///
	/// "+" is registered alongside "=" because on a US layout the plus key *is* ⇧=, and SwiftUI
	/// matches the literal key equivalent — with only "+" registered the user has to hold shift.
	/// Yielded while a sheet is up for the same reason ⌘W is: the staging panel and the graph are
	/// separate windows with their own idea of what a keystroke means.
	@ViewBuilder
	private var zoomShortcuts: some View {
		if store.stagingDetail == nil, store.gitGraph == nil {
			Group {
				Button("") { store.send(.zoomInRequested) }
					.keyboardShortcut("+", modifiers: .command)
				Button("") { store.send(.zoomInRequested) }
					.keyboardShortcut("=", modifiers: .command)
				Button("") { store.send(.zoomOutRequested) }
					.keyboardShortcut("-", modifiers: .command)
				Button("") { store.send(.resetZoomRequested) }
					.keyboardShortcut("0", modifiers: .command)
			}
			.hidden()
		}
	}

	/// ⌘G / ⇧⌘G / ⌘E drive SwiftTerm's find bar in the active pane — the standard Find menu
	/// shortcuts, registered here because the app has no Find menu for SwiftTerm to hang them on.
	/// ⌘F, which opens the bar, is `RepositoryListView`'s (it doubles as the list's filter shortcut);
	/// Escape and Return are the find bar's own (close, next; ⇧Return for previous).
	///
	/// The session is read from the store when the key is pressed, not captured, for the reason
	/// ⌘W documents: SwiftUI can keep the closure a hidden button was first laid out with. Yielded
	/// while a sheet is up for the same reason the zoom shortcuts are.
	@ViewBuilder
	private var findShortcuts: some View {
		if store.stagingDetail == nil, store.gitGraph == nil {
			Group {
				Button("") { find(.next) }
					.keyboardShortcut("g", modifiers: .command)
				Button("") { find(.previous) }
					.keyboardShortcut("g", modifiers: [.command, .shift])
				Button("") { find(.useSelection) }
					.keyboardShortcut("e", modifiers: .command)
			}
			.hidden()
		}
	}

	private func find(_ command: TerminalFindCommand) {
		if let sessionId = store.activeSessionId {
			terminalViewStore.performFind(command, sessionId: sessionId)
		}
	}
}
