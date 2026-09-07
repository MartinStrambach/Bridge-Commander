import ComposableArchitecture
import SwiftUI
import Settings
import TerminalFeature

struct TerminalLayoutView: View {
	@Bindable var store: StoreOf<TerminalLayoutReducer>

	/// Group stores rather than group values so every sidebar row observes its own state. Handing
	/// the rows down as values froze their counts: TCA's `IdentifiedArray` observation compares
	/// element ids, so a row's changed badge never invalidated this view. Materialised into an
	/// array by the parent, as a scoped store collection requires inside a lazy container.
	let repositoryGroups: [StoreOf<RepoGroupReducer>]
	/// The row opened in the panel, resolved by the parent — see `RepositoryListView.activeRowStore`.
	let activeRowStore: StoreOf<RepositoryRowReducer>?
	let sessions: IdentifiedArrayOf<TerminalSession>
	let terminalViewStore: TerminalViewStore
	let onStatusChange: @Sendable (UUID, TerminalSessionStatus) -> Void

	@AppStorage("terminalSidebar.showOnlyWithTerminals") private var showOnlyWithTerminals = false

	var body: some View {
		// Build a path → status map once so each sidebar row, the home row and the terminal
		// filter all do an O(1) lookup instead of scanning the whole sessions array.
		// Same reasoning as RepositoryListView.repositoryListView.
		let statusByPath = Dictionary(
			sessions.map { ($0.repositoryPath, $0.status) },
			uniquingKeysWith: { first, _ in first }
		)
		return HStack(spacing: 0) {
			sidebar(statusByPath: statusByPath)
				.frame(width: 200)

			Divider()

			TerminalPanelView(
				store: store,
				activeRowStore: activeRowStore,
				terminalViewStore: terminalViewStore,
				sessions: sessions,
				activeSessionId: store.activeSessionId,
				onStatusChange: onStatusChange,
				onRetry: { sessionId in
					terminalViewStore.killSession(sessionId: sessionId)
					store.send(.retryTab(sessionId: sessionId))
				},
				onNewTab: {
					store.send(.newTabRequested)
				},
				onSelectTab: { sessionId in
					store.send(.selectTab(sessionId: sessionId))
				},
				onKillTab: { sessionId in
					terminalViewStore.killSession(sessionId: sessionId)
					store.send(.killTab(sessionId: sessionId))
				}
			)
		}
	}

	// MARK: - Sidebar

	private func sidebar(statusByPath: [String: TerminalSessionStatus]) -> some View {
		VStack(spacing: 0) {
			HStack {
				Text("REPOSITORIES")
					.font(.caption2)
					.fontWeight(.semibold)
					.foregroundColor(.secondary)
				Spacer()
				Button {
					showOnlyWithTerminals.toggle()
				} label: {
					Image(systemName: showOnlyWithTerminals ? "terminal.fill" : "terminal")
						.font(.caption)
						.foregroundColor(showOnlyWithTerminals ? .green : .secondary)
						.padding(8)
						.background(Color.secondary.opacity(showOnlyWithTerminals ? 0.2 : 0.1), in: RoundedRectangle(cornerRadius: 6))
						.contentShape(Rectangle())
				}
				.buttonStyle(.plain)
				.help(showOnlyWithTerminals ? "Showing only repos with active terminals" : "Show only repos with active terminals")
			}
			.padding(.horizontal, 8)
			.padding(.top, 12)
			.padding(.bottom, 4)

			ScrollView {
				LazyVStack(alignment: .leading, spacing: 2) {
					if let status = statusByPath[NSHomeDirectory()] {
						homeSessionRow(status: status)
					}
					// Every group is walked and resolves the terminal filter against its own rows,
					// rather than the sidebar pre-building a filtered copy of the groups: that
					// copy was plain values, which is what went stale. Same shape as RepoGroupView.
					ForEach(repositoryGroups) { groupStore in
						sidebarGroup(groupStore, statusByPath: statusByPath)
					}
				}
				.padding(.vertical, 4)
			}

			Spacer()

			Divider()

			Button("← Show full list") {
				store.send(.hideTerminalMode)
			}
			.buttonStyle(.plain)
			.font(.caption)
			.foregroundColor(.secondary)
			.padding(12)
			.frame(maxWidth: .infinity, alignment: .leading)
		}
		.background(Color(NSColor.controlBackgroundColor))
		.background {
			Button("") { store.send(.hideTerminalMode) }
				.keyboardShortcut("§", modifiers: .command)
				.hidden()
			// ⌘R here refreshes only the repo opened in the terminal; the full-list
			// refresh in RepositoryListView hands the shortcut off while we're open.
			// The staging sheet and the commit graph claim ⌘R for their own refresh, so yield
			// it there — a shortcut registered twice dispatches to either owner at random.
			if store.stagingDetail == nil, store.gitGraph == nil {
				Button("") { store.send(.refreshActiveRepoRequested) }
					.keyboardShortcut("r", modifiers: .command)
					.hidden()
			}
		}
	}

	/// One group's label, header row and worktree rows, or nothing at all when the terminal
	/// filter is on and none of its rows has a session.
	@ViewBuilder
	private func sidebarGroup(
		_ groupStore: StoreOf<RepoGroupReducer>,
		statusByPath: [String: TerminalSessionStatus]
	) -> some View {
		let showsHeader = !showOnlyWithTerminals || statusByPath[groupStore.header.path] != nil
		// Row ids are repository paths, so whether a worktree has a session is answerable from
		// the group's ids alone — no need to read any row's state to lay the group out.
		let hasVisibleWorktrees = groupStore.worktrees.ids.contains { statusByPath[$0] != nil }

		if showsHeader || hasVisibleWorktrees {
			sidebarGroupLabel(rootPath: groupStore.id)
			if showsHeader {
				sidebarRow(for: groupStore.scope(\.header, action: \.header), statusByPath: statusByPath)
			}
			ForEach(Array(groupStore.scope(\.worktrees, action: \.worktrees))) { rowStore in
				if !showOnlyWithTerminals || statusByPath[rowStore.id] != nil {
					sidebarRow(for: rowStore, statusByPath: statusByPath)
				}
			}
		}
	}

	private func sidebarGroupLabel(rootPath: String) -> some View {
		Text(URL(fileURLWithPath: rootPath).lastPathComponent.uppercased())
			.font(.caption2)
			.fontWeight(.semibold)
			.foregroundColor(.secondary)
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding(.horizontal, 8)
			.padding(.top, 8)
			.padding(.bottom, 2)
	}

	private func homeSessionRow(status: TerminalSessionStatus) -> some View {
		let isActive = store.activeRepositoryPath == NSHomeDirectory()
		return Button {
			store.send(.selectRepo(repositoryPath: NSHomeDirectory()))
		} label: {
			HStack(spacing: 8) {
				TerminalStatusDotView(status: status, size: 12)
				VStack(alignment: .leading, spacing: 2) {
					Text("Home Directory")
						.font(.caption)
						.fontWeight(isActive ? .semibold : .regular)
						.foregroundColor(isActive ? .primary : .secondary)
						.lineLimit(1)
					Text("~")
						.font(.caption2)
						.foregroundColor(.secondary)
						.lineLimit(1)
				}
				Spacer()
			}
			.padding(.horizontal, 8)
			.padding(.vertical, 6)
			.background(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
			.cornerRadius(6)
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.padding(.horizontal, 4)
		.contextMenu {
			Button("Kill Terminal", role: .destructive) {
				terminalViewStore.killAllSessions(for: NSHomeDirectory())
				store.send(.killRepo(repositoryPath: NSHomeDirectory()))
			}
		}
	}

	private func sidebarRow(
		for rowStore: StoreOf<RepositoryRowReducer>,
		statusByPath: [String: TerminalSessionStatus]
	) -> some View {
		let path = rowStore.path
		return SidebarRepositoryRowView(
			store: rowStore,
			isActive: store.activeRepositoryPath == path,
			sessionStatus: statusByPath[path],
			onTap: {
				store.send(.selectRepo(repositoryPath: path))
			},
			onKill: {
				terminalViewStore.killAllSessions(for: path)
				store.send(.killRepo(repositoryPath: path))
			}
		)
		.padding(.horizontal, 4)
	}

}
