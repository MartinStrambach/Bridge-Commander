import ComposableArchitecture
import SwiftUI
import Settings
import TerminalFeature

struct TerminalLayoutView: View {
	@Bindable var store: StoreOf<TerminalLayoutReducer>

	let repositoryGroups: IdentifiedArrayOf<RepoGroupReducer.State>
	let sessions: IdentifiedArrayOf<TerminalSession>
	let terminalViewStore: TerminalViewStore
	let onStatusChange: @Sendable (UUID, TerminalSessionStatus) -> Void

	@AppStorage("terminalSidebar.showOnlyWithTerminals") private var showOnlyWithTerminals = false

	// MARK: - Helpers

	private func filteredSidebarGroups(
		statusByPath: [String: TerminalSessionStatus]
	) -> [(group: RepoGroupReducer.State, showHeader: Bool, worktrees: [RepositoryRowReducer.State])] {
		repositoryGroups.compactMap { group in
			let showHeader = statusByPath[group.header.path] != nil
			let filteredWorktrees = group.worktrees.filter { statusByPath[$0.path] != nil }
			guard showHeader || !filteredWorktrees.isEmpty else { return nil }
			return (group, showHeader, Array(filteredWorktrees))
		}
	}

	private var activeRowState: RepositoryRowReducer.State? {
		guard let path = store.activeRepositoryPath else {
			return nil
		}

		for group in repositoryGroups {
			if group.header.path == path {
				return group.header
			}
			if let wt = group.worktrees[id: path] {
				return wt
			}
		}
		return nil
	}

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
				activeRowState: activeRowState,
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
					if showOnlyWithTerminals {
						ForEach(filteredSidebarGroups(statusByPath: statusByPath), id: \.group.id) { item in
							sidebarGroupLabel(for: item.group)
							if item.showHeader {
								sidebarRow(for: item.group.header, statusByPath: statusByPath)
							}
							ForEach(item.worktrees, id: \.id) { rowState in
								sidebarRow(for: rowState, statusByPath: statusByPath)
							}
						}
					} else {
						ForEach(repositoryGroups) { group in
							sidebarGroupLabel(for: group)
							sidebarRow(for: group.header, statusByPath: statusByPath)
							ForEach(group.worktrees) { rowState in
								sidebarRow(for: rowState, statusByPath: statusByPath)
							}
						}
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
			// The staging sheet claims ⌘R for its own refresh, so yield it there.
			if store.stagingDetail == nil {
				Button("") { store.send(.refreshActiveRepoRequested) }
					.keyboardShortcut("r", modifiers: .command)
					.hidden()
			}
		}
	}

	private func sidebarGroupLabel(for group: RepoGroupReducer.State) -> some View {
		Text(URL(fileURLWithPath: group.id).lastPathComponent.uppercased())
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
		for rowState: RepositoryRowReducer.State,
		statusByPath: [String: TerminalSessionStatus]
	) -> some View {
		SidebarRepositoryRowView(
			rowState: rowState,
			isActive: store.activeRepositoryPath == rowState.path,
			sessionStatus: statusByPath[rowState.path],
			onTap: {
				store.send(.selectRepo(repositoryPath: rowState.path))
			},
			onKill: {
				terminalViewStore.killAllSessions(for: rowState.path)
				store.send(.killRepo(repositoryPath: rowState.path))
			}
		)
		.padding(.horizontal, 4)
	}

}
