// BridgeCommander/TerminalMode/TerminalLayoutView.swift
import ComposableArchitecture
import SwiftUI

struct TerminalLayoutView: View {
    @Bindable var store: StoreOf<TerminalLayoutReducer>
    let repositories: IdentifiedArrayOf<RepositoryRowReducer.State>
    let sessions: IdentifiedArrayOf<TerminalSession>
    let terminalViewStore: TerminalViewStore
    let onStatusChange: @Sendable (String, TerminalSessionStatus) -> Void

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
                onStatusChange: onStatusChange,
                onRetry: { repositoryPath in
                    terminalViewStore.removeSession(for: repositoryPath)
                    store.send(.sessionStatusChanged(repositoryPath: repositoryPath, status: .launching))
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
                LazyVStack(spacing: 2) {
                    ForEach(repositories) { rowState in
                        SidebarRepositoryRowView(
                            rowState: rowState,
                            isActive: store.activeRepositoryPath == rowState.path,
                            hasTerminalSession: sessions[id: rowState.path] != nil,
                            onTap: {
                                store.send(.selectRepo(repositoryPath: rowState.path))
                            }
                        )
                        .padding(.horizontal, 4)
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
    }

    // MARK: - Helpers

    private var activeRowState: RepositoryRowReducer.State? {
        guard let path = store.activeRepositoryPath else { return nil }
        return repositories[id: path]
    }
}
