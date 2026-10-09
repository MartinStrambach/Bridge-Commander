import ActionButtons
import AppKit
import AppUI
import ComposableArchitecture
import GitActionsMenu
import GitGraphFeature
import StagingFeature
import SwiftTerm
import SwiftUI
import Settings
import SimulatorFeature
import TerminalFeature
import ToolsIntegration
import YouTrackMenu

struct TerminalPanelView: View {
	@Bindable
	var store: StoreOf<TerminalLayoutReducer>

	@Shared(.terminalColorTheme)
	private var terminalColorTheme = TerminalThemeSelection.builtIn(.basicDark)

	@Shared(.terminalProfiles)
	private var terminalProfiles: [TerminalProfile] = []

	@Shared(.terminalCopyOnSelect)
	private var terminalCopyOnSelect = false

	@Shared(.terminalMouseReporting)
	private var terminalMouseReporting = true

	@Shared(.terminalClaudeStatusDetection)
	private var terminalClaudeStatusDetection = ClaudeStatusDetection.default

	/// The setting in TerminalFeature's terms, mapped here so that package needs no Settings
	/// dependency.
	private var claudeStatusSource: ClaudeStatusSource {
		switch terminalClaudeStatusDetection {
		case .progressAndScreen:
			.progressAndScreen
		case .progressOnly:
			.progressOnly
		case .screenOnly:
			.screenOnly
		}
	}

	/// Read here like its sibling settings; the ⌘+/⌘−/⌘0 shortcuts write it through
	/// `TerminalLayoutReducer` so the zoom actions stay testable.
	@Shared(.terminalFontSize)
	private var terminalFontSize = TerminalFontSize.default

	@Shared(.terminalFontName)
	private var terminalFontName = TerminalFontFamily.systemDefault

	/// The two font settings resolved into the one font the panes render with. Resolved here, like
	/// the theme above, so TerminalFeature needs no Settings dependency.
	private var terminalFont: NSFont {
		TerminalFontFamily.resolve(name: terminalFontName, size: terminalFontSize)
	}

	/// The selected theme looked up against the imported profiles.
	private var resolvedTheme: ResolvedTerminalTheme {
		terminalColorTheme.resolve(profiles: terminalProfiles)
	}

	/// The opened repository's row. A store rather than a plain value so the counts and badges
	/// in the toolbar track the row's refreshes — see `SidebarRepositoryRowView.store`.
	let activeRowStore: StoreOf<RepositoryRowReducer>?
	let terminalViewStore: TerminalViewStore
	let sessions: IdentifiedArrayOf<TerminalSession>
	let activeSessionId: UUID?
	let onStatusChange: @Sendable (UUID, TerminalSessionStatus) -> Void
	let onNotification: @Sendable (UUID, TerminalNotification) -> Void
	let onRetry: (UUID) -> Void
	let onNewTab: () -> Void
	let onSelectTab: (UUID) -> Void
	let onKillTab: (UUID) -> Void

	/// The tab being dragged, set when its drag starts and read by every other tab's drop
	/// delegate to move it as the pointer passes over them. Local to the view: nothing outside
	/// it reads a drag in flight.
	@State
	private var draggedTabId: UUID?

	var body: some View {
		VStack(spacing: 0) {
			toolbar
			Divider()
			// The flag comes from the panel's own menu copy, which is the state the menu view
			// beside this banner acts on, and which is re-synced on every merge-status report
			// from the opened row. `activeRowStore?.gitActionsMenu` would be equivalent now
			// that the row is a store — this keeps banner and menu on one source.
			if store.gitActionsMenu?.isMergeInProgress == true {
				mergeStatusBanner
			}
			if store.activeRepositoryPath != nil {
				tabBar
				Divider()
			}
			terminalContent
		}
		.sheet(
			item: $store.scope(\.$stagingDetail, action: \.stagingDetail)
		) { detailStore in
			RepositoryDetailView(store: detailStore)
				.frame(
					minWidth: 1400,
					idealWidth: 1500,
					maxWidth: .infinity,
					minHeight: 700,
					idealHeight: 800,
					maxHeight: .infinity
				)
		}
		.sheet(
			item: $store.scope(\.$gitGraph, action: \.gitGraph)
		) { graphStore in
			GitGraphView(store: graphStore)
				// Roomier than the graph alone needs: the selected commit's diff opens in a
				// bottom pane, and both panes have to stay usable at the ideal size.
				.frame(
					minWidth: 1000,
					idealWidth: 1400,
					maxWidth: .infinity,
					minHeight: 600,
					idealHeight: 900,
					maxHeight: .infinity
				)
				.windowResizable()
		}
	}

	// MARK: - Toolbar

	private var toolbar: some View {
		HStack(spacing: 8) {
			if let rowStore = activeRowStore {
				if let ticketId = rowStore.ticketId {
					Text(ticketId)
						.scaledFont(.caption)
						.fontWeight(.medium)
						.foregroundStyle(.secondary)
						.padding(.horizontal, 5)
						.padding(.vertical, 2)
						.background(.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
						.layoutPriority(1)
				}

				Text(rowStore.formattedBranchName)
					.scaledFont(.subheadline)
					.fontWeight(.semibold)
					.lineLimit(1)

				Text("·")
					.foregroundColor(.secondary)

				Text(rowStore.name)
					.scaledFont(.subheadline)
					.foregroundColor(.secondary)
					.lineLimit(1)
			}

			Spacer()

			if let gitActionsStore = store.scope(\.gitActionsMenu, action: \.gitActionsMenu) {
				GitActionsMenuView(store: gitActionsStore)
			}

			// The row's own stores, not copies, so a generate shows the same progress here and in
			// the list and survives the panel being hidden. Gated the same way as in the row.
			if let rowStore = activeRowStore, rowStore.supportsIOS, rowStore.supportsTuist {
				TuistButtonView(store: rowStore.scope(\.tuistButton, action: \.tuistButton))
			}

			// The row's own store too: after a transition the row refetches the ticket, and only
			// that fetch knows the transitions now reachable — a copy here would keep offering
			// the old ones.
			if let youtrackStore = activeRowStore?.scope(\.youtrackButton, action: \.youtrackButton) {
				YouTrackButtonView(store: youtrackStore)
			}

			if let rowStore = activeRowStore, rowStore.unpushedCommitCount > 0 || store.isPushing {
				Button {
					if let path = store.activeRepositoryPath {
						store.send(.pushButtonTapped(repositoryPath: path))
					}
				} label: {
					if store.isPushing {
						HStack(spacing: 4) {
							ProgressView()
								.controlSize(.mini)
							Text("Pushing…")
						}
					}
					else {
						Text("Push (\(rowStore.unpushedCommitCount))")
					}
				}
				.buttonStyle(.scaledBordered)
				.controlSize(.small)
				.tint(.orange)
				.disabled(store.isPushing)
			}

			// PR/MR fetch failure (conditional) — same indicator, in the same position, as
			// `RepositoryRowView`. A failed provider fetch keeps the last-known PR state
			// rather than clearing it (see `RepositoryRowReducer.fetchPullRequest`), so
			// without this the badge here is indistinguishable from one ⌘R never refreshed.
			if let prFetchError = activeRowStore?.prFetchError {
				Image(systemName: "exclamationmark.triangle.fill")
					.resizable()
					.scaledToFit()
					.padding(4)
					.frame(width: 22, height: 22)
					.foregroundColor(.orange)
					.help(prFetchError)
			}

			if let prUrl = activeRowStore?.prUrl, let url = URL(string: prUrl) {
				VStack(alignment: .center, spacing: 2) {
					PullRequestButton(
						url: url,
						provider: activeRowStore?.prProvider,
						state: activeRowStore?.prState
					)

					if let count = activeRowStore?.prUnresolvedDiscussions, count > 0 {
						UnresolvedDiscussionsBadge(
							count: count,
							url: url,
							provider: activeRowStore?.prProvider
						)
					}
				}
				// Keeps the badge's count text from being compressed away when the
				// toolbar runs out of width; also pins the badge to the button's width.
				.fixedSize(horizontal: true, vertical: false)
			}

			if let pipelineUrl = activeRowStore?.pipelineUrl,
			   let url = URL(string: pipelineUrl),
			   let pipelineState = activeRowStore?.pipelineState {
				PipelineStatusButton(
					url: url,
					state: pipelineState,
					hasConflicts: activeRowStore?.prHasConflicts == true
				)
			}

			if let slot = activeRowStore?.approvalSlot,
			   let prUrl = activeRowStore?.prUrl,
			   let url = URL(string: prUrl) {
				ApprovalSlotView(slot: slot, url: url, provider: activeRowStore?.prProvider)
			}

			if let ticketStore = store.scope(\.ticketButton, action: \.ticketButton) {
				TicketButtonView(store: ticketStore)
			}

			if let rowStore = activeRowStore, rowStore.supportsIOS {
				XcodeProjectButtonView(
					store: rowStore.scope(\.xcodeButton, action: \.xcodeButton),
					style: .compact
				)
			}

			if let androidStore = store.scope(\.androidStudioButton, action: \.androidStudioButton) {
				AndroidStudioButtonView(store: androidStore, style: .compact)
			}

			if let webStore = store.scope(\.webButton, action: \.webButton) {
				WebButtonView(store: webStore, style: .compact)
			}

//			if let rowStore = activeRowStore, rowStore.stagedChangesCount > 0 {
//				Button("Commit") {
//					if let path = store.activeRepositoryPath {
//						store.send(.stagingButtonTapped(repositoryPath: path))
//					}
//				}
//				.buttonStyle(.scaledBordered)
//				.controlSize(.small)
//			}
			
			if let path = store.activeRepositoryPath,
			   activeRowStore?.supportsIOS == true || isSimulatorPaneVisible {
				Button {
					store.send(.simulatorPane(.toggleVisibility(repositoryPath: path)))
				} label: {
					Label("Simulator", systemImage: "iphone")
						.labelStyle(.titleAndIcon)
				}
				.buttonStyle(.scaledBordered)
				.controlSize(.small)
				.tint(isSimulatorPaneVisible ? .accentColor : nil)
				.help(isSimulatorPaneVisible ? "Hide the iOS simulator" : "Show the iOS simulator beside the terminal")
			}

			Button("Graph") {
				if let path = store.activeRepositoryPath {
					store.send(.gitGraphButtonTapped(
						repositoryPath: path,
						repositoryName: activeRowStore?.name ?? ""
					))
				}
			}
			.buttonStyle(.scaledBordered)
			.controlSize(.small)
			.help("Show commit graph")

			Button("Staging") {
				if let path = store.activeRepositoryPath {
					store.send(.stagingButtonTapped(
						repositoryPath: path,
						iosSubfolderPath: activeRowStore?.iosSubfolderPath ?? ""
					))
				}
			}
			.buttonStyle(.scaledBordered)
			.controlSize(.small)

			Button("← Hide") {
				store.send(.hideTerminalMode)
			}
			.buttonStyle(.scaledBordered)
			.controlSize(.small)
		}
		.padding(.horizontal, 12)
		.padding(.vertical, 8)
		// Before the color: a background added after it would sit behind the color, which takes
		// the clicks.
		.windowTitleBarArea()
		.background(Color(NSColor.windowBackgroundColor))
	}

	// MARK: - Merge Status Banner

	private var mergeStatusBanner: some View {
		BannerView(
			icon: "arrow.triangle.merge",
			title: "Merge in Progress",
			actionLabel: "Finish Merge",
			actionSystemImage: "checkmark.circle",
			actionHelp: "Complete merge with git commit --no-edit",
			isLoading: store.isFinishingMerge,
			onAction: {
				if let path = store.activeRepositoryPath {
					store.send(.finishMergeButtonTapped(repositoryPath: path))
				}
			}
		)
	}

	// MARK: - Tab Bar

	private var tabBar: some View {
		let repoSessions = store.activeRepositoryPath.map { path in
			sessions.filter { $0.repositoryPath == path }
		} ?? []

		return ScrollView(.horizontal, showsIndicators: false) {
			HStack(spacing: 4) {
				ForEach(repoSessions) { session in
					tabPill(session: session, totalCount: repoSessions.count)
				}

				Button(action: onNewTab) {
					Image(systemName: "plus")
						.scaledFont(size: 11)
						.padding(.horizontal, 6)
						.padding(.vertical, 4)
						.contentShape(Rectangle())
				}
				.buttonStyle(.borderless)
				.help("New Tab")
				.keyboardShortcut("t", modifiers: .command)

				// Hidden buttons for Cmd+1…Cmd+9 tab switching
				ForEach(Array(repoSessions.prefix(9).enumerated()), id: \.element.id) { index, session in
					let key = KeyEquivalent(Character(String(index + 1)))
					Button("") { onSelectTab(session.id) }
						.keyboardShortcut(key, modifiers: .command)
						.hidden()
				}

				cycleTabShortcuts
				closeTabShortcut(repoSessions: repoSessions)
				refreshShortcut
				zoomShortcuts
				findShortcuts
			}
			.padding(.horizontal, 8)
			.padding(.vertical, 4)
		}
		.background(Color(NSColor.windowBackgroundColor))
	}

	// MARK: - Terminal Content

	/// A single NSView container hosts all terminal sessions as direct subviews
	/// and shows/hides them via isHidden. This keeps every LocalProcessTerminalView
	/// in a stable position in the view hierarchy across repo switches and
	/// hide/show cycles, preventing the zero-frame setFrameSize that would
	/// send a spurious SIGWINCH and cause zsh to clear visible terminal output.
	///
	/// The simulator pane sits to the right of that container, as a sibling in an `HStack` whose
	/// first child is always the container — showing or hiding the pane changes the terminal's
	/// width (one deliberate SIGWINCH), never its place in the hierarchy. The container resizes
	/// only the pane on screen, so the width change does not reach other repositories' shells.
	/// Whether the repository on screen has the simulator open beside its terminal — each
	/// repository's is shown or hidden on its own.
	private var isSimulatorPaneVisible: Bool {
		store.simulatorPane.isVisible(in: store.activeRepositoryPath)
	}

	private var terminalContent: some View {
		GeometryReader { proxy in
			HStack(spacing: 0) {
				terminalStack

				if let path = store.activeRepositoryPath, isSimulatorPaneVisible {
					let runTab = sessions.first { $0.repositoryPath == path && $0.isRunTab }
					Divider()
					SimulatorPaneView(
						store: store.scope(\.simulatorPane, action: \.simulatorPane),
						availableSize: proxy.size,
						repositoryPath: path,
						projectPath: activeRowStore?.xcodeButton.projectPath,
						hasRunTab: runTab != nil,
						onStop: {
							if let runTab {
								terminalViewStore.interrupt(sessionId: runTab.id)
							}
						}
					)
				}
			}
		}
	}

	private var terminalStack: some View {
		ZStack {
			TerminalContainerRepresentable(
				terminalViewStore: terminalViewStore,
				sessions: sessions,
				activeSessionId: activeSessionId,
				foregroundColor: resolvedTheme.foreground,
				backgroundColor: resolvedTheme.background,
				ansiPalette: resolvedTheme.ansiPalette,
				cursorColor: resolvedTheme.cursor,
				selectionColor: resolvedTheme.selection,
				copyOnSelect: terminalCopyOnSelect,
				mouseReporting: terminalMouseReporting,
				statusSource: claudeStatusSource,
				font: terminalFont,
				onStatusChange: onStatusChange,
				onNotification: onNotification
			)

			if
				let activeId = activeSessionId,
				let session = sessions[id: activeId],
				case let .failed(message) = session.status
			{
				terminalErrorView(message: message, sessionId: activeId)
			}

			if store.activeRepositoryPath == nil {
				VStack {
					Spacer()
					Text("Select a repository from the sidebar")
						.foregroundColor(.secondary)
					Spacer()
				}
			}
		}
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

	/// ⌃Tab / ⌃⇧Tab cycle through the repository's tabs, the shortcut Terminal.app uses. The
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

	private func tabPill(session: TerminalSession, totalCount: Int) -> some View {
		let isActive = session.id == activeSessionId
		return HStack(spacing: 4) {
			if let runTitle = session.runTitle {
				Label(runTitle, systemImage: "play.fill")
					.labelStyle(.titleAndIcon)
					.scaledFont(.caption)
					.fontWeight(isActive ? .semibold : .regular)
			}
			else {
				Text("Terminal \(session.tabIndex)")
					.scaledFont(.caption)
					.fontWeight(isActive ? .semibold : .regular)
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
		.background(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
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

	// MARK: - Error View

	private func terminalErrorView(message: String, sessionId: UUID) -> some View {
		VStack(spacing: 16) {
			Image(systemName: "exclamationmark.triangle.fill")
				.scaledFont(.largeTitle)
				.foregroundColor(.red)
			Text("Terminal failed to start")
				.scaledFont(.headline)
			Text(message)
				.scaledFont(.caption)
				.foregroundColor(.secondary)
			Button("Retry") {
				onRetry(sessionId)
			}
			.buttonStyle(.scaledBorderedProminent)
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.background(Color(NSColor.textBackgroundColor))
	}
}
