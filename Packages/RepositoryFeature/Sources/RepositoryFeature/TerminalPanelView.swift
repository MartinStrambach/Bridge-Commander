import ActionButtons
import AppUI
import ComposableArchitecture
import GitActionsMenu
import GitGraphFeature
import StagingFeature
import SwiftTerm
import SwiftUI
import Settings
import TerminalFeature
import ToolsIntegration

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

	/// Read here like its sibling settings; the ⌘+/⌘−/⌘0 shortcuts write it through
	/// `TerminalLayoutReducer` so the zoom actions stay testable.
	@Shared(.terminalFontSize)
	private var terminalFontSize = TerminalFontSize.default

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
	let onRetry: (UUID) -> Void
	let onNewTab: () -> Void
	let onSelectTab: (UUID) -> Void
	let onKillTab: (UUID) -> Void

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
						.font(.caption)
						.fontWeight(.medium)
						.foregroundStyle(.secondary)
						.padding(.horizontal, 5)
						.padding(.vertical, 2)
						.background(.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
						.layoutPriority(1)
				}

				Text(rowStore.formattedBranchName)
					.font(.subheadline)
					.fontWeight(.semibold)
					.lineLimit(1)

				Text("·")
					.foregroundColor(.secondary)

				Text(rowStore.name)
					.font(.subheadline)
					.foregroundColor(.secondary)
					.lineLimit(1)
			}

			Spacer()

			if let gitActionsStore = store.scope(\.gitActionsMenu, action: \.gitActionsMenu) {
				GitActionsMenuView(store: gitActionsStore)
			}

			if let tuistStore = store.scope(\.tuistButton, action: \.tuistButton) {
				TuistButtonView(store: tuistStore)
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
				.buttonStyle(.bordered)
				.controlSize(.small)
				.tint(.orange)
				.disabled(store.isPushing)
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
				PipelineStatusButton(url: url, state: pipelineState)
			}

			if let slot = activeRowStore?.approvalSlot,
			   let prUrl = activeRowStore?.prUrl,
			   let url = URL(string: prUrl) {
				ApprovalSlotView(slot: slot, url: url, provider: activeRowStore?.prProvider)
			}

			if let ticketStore = store.scope(\.ticketButton, action: \.ticketButton) {
				TicketButtonView(store: ticketStore)
			}

			if let xcodeStore = store.scope(\.xcodeButton, action: \.xcodeButton) {
				XcodeProjectButtonView(store: xcodeStore, style: .compact)
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
//				.buttonStyle(.bordered)
//				.controlSize(.small)
//			}
			
			Button("Graph") {
				if let path = store.activeRepositoryPath {
					store.send(.gitGraphButtonTapped(
						repositoryPath: path,
						repositoryName: activeRowStore?.name ?? ""
					))
				}
			}
			.buttonStyle(.bordered)
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
			.buttonStyle(.bordered)
			.controlSize(.small)

			Button("← Hide") {
				store.send(.hideTerminalMode)
			}
			.buttonStyle(.bordered)
			.controlSize(.small)
		}
		.padding(.horizontal, 12)
		.padding(.vertical, 8)
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
						.font(.system(size: 11))
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

				closeTabShortcut(repoSessions: repoSessions)
				zoomShortcuts
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
	private var terminalContent: some View {
		ZStack {
			TerminalContainerRepresentable(
				terminalViewStore: terminalViewStore,
				sessions: sessions,
				activeSessionId: activeSessionId,
				foregroundColor: resolvedTheme.foreground,
				backgroundColor: resolvedTheme.background,
				ansiPalette: resolvedTheme.ansiPalette,
				copyOnSelect: terminalCopyOnSelect,
				mouseReporting: terminalMouseReporting,
				fontSize: terminalFontSize,
				onStatusChange: onStatusChange
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

	/// ⌘W closes the active tab, but only while the repo has more than one. On the last tab the
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
		if repoSessions.count > 1,
		   let activeSessionId,
		   repoSessions.contains(where: { $0.id == activeSessionId }),
		   store.stagingDetail == nil,
		   store.gitGraph == nil {
			Button("") { store.send(.closeActiveTabRequested) }
				.keyboardShortcut("w", modifiers: .command)
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

	private func tabPill(session: TerminalSession, totalCount: Int) -> some View {
		let isActive = session.id == activeSessionId
		return HStack(spacing: 4) {
			Text("Terminal \(session.tabIndex)")
				.font(.caption)
				.fontWeight(isActive ? .semibold : .regular)

			if totalCount > 1 {
				Button(action: { onKillTab(session.id) }) {
					Image(systemName: "xmark")
						.font(.system(size: 8))
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
	}

	// MARK: - Error View

	private func terminalErrorView(message: String, sessionId: UUID) -> some View {
		VStack(spacing: 16) {
			Image(systemName: "exclamationmark.triangle.fill")
				.font(.largeTitle)
				.foregroundColor(.red)
			Text("Terminal failed to start")
				.font(.headline)
			Text(message)
				.font(.caption)
				.foregroundColor(.secondary)
			Button("Retry") {
				onRetry(sessionId)
			}
			.buttonStyle(.borderedProminent)
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.background(Color(NSColor.textBackgroundColor))
	}
}
