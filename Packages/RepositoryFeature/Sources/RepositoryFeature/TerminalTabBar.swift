import AppUI
import ComposableArchitecture
import SwiftUI
import TerminalFeature

/// One pane's tabs and the buttons that open another tab in it or another pane beside it. Every
/// pane of a split has its own bar, over its terminal; a panel showing one terminal has one bar.
/// The bar of the first pane also carries the panel's keyboard shortcuts, as hidden buttons, so
/// they are registered once however many panes there are.
struct TerminalTabBar: View {
	/// The toolbar's store, for the shortcuts that are its (zoom, refresh) and for whether a
	/// sheet is up.
	let store: StoreOf<TerminalLayoutReducer>
	let workspace: StoreOf<TerminalWorkspaceReducer>
	/// The pane's tabs, in bar order.
	let tabs: [TerminalSession]
	/// The tab the pane shows.
	let shownSessionId: UUID?
	/// Whose terminals the pane shows, named at the head of the bar while the panel is split —
	/// the toolbar names only the repository with the keyboard. Nil while it is not, when the
	/// bar also has no button that takes the pane away.
	var paneTitle: String?
	var hostsShortcuts = true

	/// The tab being dragged, set when its drag starts and read by every other tab's drop
	/// delegate to move it as the pointer passes over them. Local to this bar, so a tab dragged
	/// over another pane's bar moves nothing there: tabs do not change pane.
	@State
	private var draggedTabId: UUID?

	private var activeSessionId: UUID? {
		workspace.activeSessionId
	}

	/// Whether this bar's pane has the keyboard.
	private var isFocused: Bool {
		shownSessionId != nil && shownSessionId == activeSessionId
	}

	/// The tabs of the pane with the keyboard, which ⌘1…⌘9 choose among.
	private var activePaneTabs: [TerminalSession] {
		workspace.state.tabs(inPane: workspace.activePaneIndex)
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
						workspace.send(.newTabRequested)
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
						workspace.send(.splitRequested)
					} label: {
						Image(systemName: "rectangle.split.2x1")
							.scaledFont(size: 11)
							.padding(.horizontal, 6)
							.padding(.vertical, 4)
							.contentShape(Rectangle())
					}
					.buttonStyle(.borderless)
					.help("Split: a new terminal beside this one (⌘D), up to \(TerminalTabs.maxPanes) side by side")
					.disabled(!workspace.canSplit)

					if hostsShortcuts {
						shortcuts
					}
				}
				.padding(.horizontal, 8)
				.padding(.vertical, 4)
			}

			if paneTitle != nil, let shownSessionId {
				Button(action: { workspace.send(.closePane(sessionId: shownSessionId)) }) {
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
			workspace.send(.paneFocused(sessionId: shownSessionId))
		}
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
				// A program's title can be a sentence (Claude's summary of the conversation), so it
				// is cut to keep the bar from growing a tab per screen; the tooltip has all of it.
				Text(session.tabTitle)
					.scaledFont(.caption)
					.fontWeight(isShown ? .semibold : .regular)
					.lineLimit(1)
					.truncationMode(.tail)
					.frame(maxWidth: 200)
					.help(session.tabTitle)
			}

			if paneTitle != nil {
				TerminalStatusDotView(status: session.status)
			}

			if totalCount > 1 {
				Button(action: { workspace.send(.killTab(sessionId: session.id)) }) {
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
			workspace.send(.selectTab(sessionId: session.id))
		}
		.liveReorderable(
			id: session.id,
			isEnabled: totalCount > 1,
			draggedId: $draggedTabId,
			onMove: { dragged, target in
				// Animated so the pills slide into their new places rather than jump; the
				// `ForEach` is keyed by session id, which is what makes the move animatable.
				withAnimation(.snappy) {
					_ = workspace.send(.moveTab(sessionId: dragged, ontoSessionId: target))
				}
			}
		)
	}

	// MARK: - Shortcuts

	/// Whether the staging panel or the commit graph is up. They are their own windows with their
	/// own idea of what a keystroke means, so the panel's shortcuts do nothing meanwhile.
	///
	/// Most shortcuts stay registered and check this when the key is pressed: a shortcut button
	/// inserted and removed with the sheets can stop being delivered on macOS 27. ⌘W and ⌘R are
	/// the exceptions, taken out while a sheet is up — ⌘W has to fall through to File ▸ Close,
	/// and the sheets register ⌘R themselves, where two owners get the key at random.
	private var isSheetUp: Bool {
		store.stagingDetail != nil || store.gitGraph != nil
	}

	/// Sends a shortcut's action unless a sheet is up.
	private func sendUnlessSheetUp(_ action: TerminalLayoutReducer.Action) {
		if !isSheetUp {
			store.send(action)
		}
	}

	private func sendUnlessSheetUp(_ action: TerminalWorkspaceReducer.Action) {
		if !isSheetUp {
			workspace.send(action)
		}
	}

	/// Every shortcut of the panel. They act on the pane with the keyboard, whichever bar hosts
	/// them.
	@ViewBuilder
	private var shortcuts: some View {
		let repoSessions = workspace.sessions.filter { $0.repositoryPath == workspace.activeRepositoryPath }

		Group {
			Button("") { workspace.send(.newTabRequested) }
				.keyboardShortcut("t", modifiers: .command)
			Button("") { workspace.send(.splitRequested) }
				.keyboardShortcut("d", modifiers: .command)
				.disabled(!workspace.canSplit)
		}
		.hidden()

		// Hidden buttons for Cmd+1…Cmd+9 tab switching
		ForEach(Array(activePaneTabs.prefix(9).enumerated()), id: \.element.id) { index, session in
			let key = KeyEquivalent(Character(String(index + 1)))
			Button("") { workspace.send(.selectTab(sessionId: session.id)) }
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
	/// The action deliberately carries no session id, unlike `killTab`: SwiftUI held on to the
	/// closure this button was first laid out with, so a captured id killed the same,
	/// already-removed session on every press after the first. The reducer resolves the active
	/// tab instead.
	@ViewBuilder
	private func closeTabShortcut(repoSessions: some Collection<TerminalSession>) -> some View {
		let hasOtherRepoSessions = workspace.sessions.contains { $0.repositoryPath != workspace.activeRepositoryPath }
		if repoSessions.count > 1 || hasOtherRepoSessions,
		   let activeSessionId,
		   repoSessions.contains(where: { $0.id == activeSessionId }),
		   !isSheetUp {
			Button("") { workspace.send(.closeActiveTabRequested) }
				.keyboardShortcut("w", modifiers: .command)
				.hidden()
		}
	}

	/// ⌃Tab / ⌃⇧Tab cycle through the active pane's tabs, the shortcut Terminal.app uses. The
	/// reducer resolves the active tab when the key fires, for the reason ⌘W documents.
	private var cycleTabShortcuts: some View {
		Group {
			Button("") { sendUnlessSheetUp(.cycleTabRequested(forward: true)) }
				.keyboardShortcut(.tab, modifiers: .control)
			Button("") { sendUnlessSheetUp(.cycleTabRequested(forward: false)) }
				.keyboardShortcut(.tab, modifiers: [.control, .shift])
		}
		.hidden()
	}

	/// ⌘] / ⌘[ move the keyboard between the panes of the split, the shortcuts iTerm uses. The
	/// reducer resolves the active pane when the key fires, for the reason ⌘W documents.
	private var cyclePaneShortcuts: some View {
		Group {
			Button("") { sendUnlessSheetUp(.cyclePaneRequested(forward: true)) }
				.keyboardShortcut("]", modifiers: .command)
			Button("") { sendUnlessSheetUp(.cyclePaneRequested(forward: false)) }
				.keyboardShortcut("[", modifiers: .command)
		}
		.hidden()
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
		if !isSheetUp {
			Button("") { store.send(.refreshActiveRepoRequested) }
				.keyboardShortcut("r", modifiers: .command)
				.hidden()
		}
	}

	/// ⌘+ / ⌘− / ⌘0 zoom the terminal font, the shortcuts every terminal emulator uses.
	///
	/// "+" is registered alongside "=" because on a US layout the plus key *is* ⇧=, and SwiftUI
	/// matches the literal key equivalent — with only "+" registered the user has to hold shift.
	private var zoomShortcuts: some View {
		Group {
			Button("") { sendUnlessSheetUp(.zoomInRequested) }
				.keyboardShortcut("+", modifiers: .command)
			Button("") { sendUnlessSheetUp(.zoomInRequested) }
				.keyboardShortcut("=", modifiers: .command)
			Button("") { sendUnlessSheetUp(.zoomOutRequested) }
				.keyboardShortcut("-", modifiers: .command)
			Button("") { sendUnlessSheetUp(.resetZoomRequested) }
				.keyboardShortcut("0", modifiers: .command)
		}
		.hidden()
	}

	/// ⌘G / ⇧⌘G / ⌘E drive SwiftTerm's find bar in the active pane — the standard Find menu
	/// shortcuts, registered here because the app has no Find menu for SwiftTerm to hang them on.
	/// ⌘F, which opens the bar, is `RepositoryListView`'s (it doubles as the list's filter shortcut);
	/// Escape and Return are the find bar's own (close, next; ⇧Return for previous).
	///
	/// The reducer resolves the session when the key is pressed, for the reason ⌘W documents:
	/// SwiftUI can keep the closure a hidden button was first laid out with.
	private var findShortcuts: some View {
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

	private func find(_ command: TerminalFindCommand) {
		sendUnlessSheetUp(.findRequested(command))
	}
}
