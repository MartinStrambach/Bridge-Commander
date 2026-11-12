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
	/// The opened repository's row. A store rather than a plain value so the counts and badges
	/// in the toolbar track the row's refreshes — see `SidebarRepositoryRowView.store`.
	let activeRowStore: StoreOf<RepositoryRowReducer>?
	/// The Xcode project of a repository's row, for the simulator pane, which in a split can be
	/// beside a repository other than the active one.
	let xcodeProjectPath: (String) -> String?
	let terminalViewStore: TerminalViewStore
	let sessions: IdentifiedArrayOf<TerminalSession>
	let onStatusChange: @Sendable (UUID, TerminalSessionStatus) -> Void
	let onNotification: @Sendable (UUID, TerminalNotification) -> Void
	let onOpenFile: @Sendable (UUID, TerminalFileLink) -> Void
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
						.padding(.horizontal, 4)
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
					isMergeTrain: activeRowStore?.pipelineIsMergeTrain == true,
					mergeTrain: activeRowStore?.prMergeTrain,
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
	// MARK: - Terminal Content

	/// The simulator pane sits to the right of the terminals, as a sibling in an `HStack` whose
	/// first child is always the split — showing or hiding the pane changes the terminals' width
	/// (one deliberate SIGWINCH for each on screen), never their place in the hierarchy. Hidden
	/// terminals are not resized, so the width change does not reach other repositories' shells.
	/// Whether the active repository has the simulator open, which is what its toolbar button
	/// shows and toggles.
	private var isSimulatorPaneVisible: Bool {
		store.simulatorPane.isVisible(in: store.activeRepositoryPath)
	}

	/// The repository whose simulator is shown beside the terminals — each repository's is shown
	/// or hidden on its own. It is the active repository's when that has it open, and otherwise
	/// that of the first pane whose repository does: in a split of a repository with the simulator
	/// and one without, moving the keyboard between the panes must not show and hide it, which
	/// would resize every terminal on screen each time.
	private var simulatorRepositoryPath: String? {
		let panePaths = store.paneSessionIds.compactMap { sessions[id: $0]?.repositoryPath }
		return ([store.activeRepositoryPath].compactMap(\.self) + panePaths)
			.first { store.simulatorPane.isVisible(in: $0) }
	}

	private var terminalContent: some View {
		GeometryReader { proxy in
			HStack(spacing: 0) {
				TerminalSplitView(
					store: store,
					sessions: sessions,
					terminalViewStore: terminalViewStore,
					onStatusChange: onStatusChange,
					onNotification: onNotification,
					onOpenFile: onOpenFile,
					onRetry: onRetry,
					onNewTab: onNewTab,
					onSelectTab: onSelectTab,
					onKillTab: onKillTab
				)

				if let path = simulatorRepositoryPath {
					let runTab = sessions.first { $0.repositoryPath == path && $0.isRunTab }
					Divider()
					SimulatorPaneView(
						store: store.scope(\.simulatorPane, action: \.simulatorPane),
						availableSize: proxy.size,
						repositoryPath: path,
						projectPath: xcodeProjectPath(path),
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
}
