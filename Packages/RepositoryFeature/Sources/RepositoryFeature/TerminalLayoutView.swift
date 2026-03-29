// BridgeCommander/TerminalMode/TerminalLayoutView.swift
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

	// MARK: - Helpers

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
		HStack(spacing: 0) {
			sidebar
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

	private var sidebar: some View {
		VStack(spacing: 0) {
			Text("REPOSITORIES")
				.font(.caption2)
				.fontWeight(.semibold)
				.foregroundColor(.secondary)
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(.horizontal, 8)
				.padding(.top, 12)
				.padding(.bottom, 4)

			ScrollView {
				LazyVStack(alignment: .leading, spacing: 2) {
					ForEach(repositoryGroups) { group in
						Text(URL(fileURLWithPath: group.id).lastPathComponent.uppercased())
							.font(.caption2)
							.fontWeight(.semibold)
							.foregroundColor(.secondary)
							.frame(maxWidth: .infinity, alignment: .leading)
							.padding(.horizontal, 8)
							.padding(.top, 8)
							.padding(.bottom, 2)

						SidebarRepositoryRowView(
							rowState: group.header,
							isActive: store.activeRepositoryPath == group.header.path,
							sessionStatus: sessions.first(where: { $0.repositoryPath == group.header.path })?.status,
							onTap: {
								store.send(.selectRepo(repositoryPath: group.header.path))
							},
							onKill: {
								terminalViewStore.killAllSessions(for: group.header.path)
								store.send(.killRepo(repositoryPath: group.header.path))
							}
						)
						.padding(.horizontal, 4)

						ForEach(group.worktrees) { rowState in
							SidebarRepositoryRowView(
								rowState: rowState,
								isActive: store.activeRepositoryPath == rowState.path,
								sessionStatus: sessions.first(where: { $0.repositoryPath == rowState.path })?.status,
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
		}
	}

}
