// BridgeCommander/TerminalMode/TerminalPanelView.swift
import ComposableArchitecture
import SwiftUI
import SwiftTerm

struct TerminalPanelView: View {
    @Bindable var store: StoreOf<TerminalLayoutReducer>
    let activeRowState: RepositoryRowReducer.State?
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
            if store.activeRepositoryPath != nil {
                tabBar
                Divider()
            }
            terminalContent
        }
        .sheet(
            item: $store.scope(state: \.stagingDetail, action: \.stagingDetail)
        ) { detailStore in
            RepositoryDetailView(store: detailStore)
                .frame(
                    minWidth: 1200,
                    idealWidth: 1500,
                    maxWidth: .infinity,
                    minHeight: 700,
                    idealHeight: 800,
                    maxHeight: .infinity
                )
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            if let rowState = activeRowState {
                Text(rowState.formattedBranchName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                Text("·")
                    .foregroundColor(.secondary)

                Text(rowState.name)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let rowState = activeRowState, rowState.stagedChangesCount > 0 {
                Button("Commit") {
                    if let path = store.activeRepositoryPath {
                        store.send(.stagingButtonTapped(repositoryPath: path))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if let rowState = activeRowState, rowState.unpushedCommitCount > 0 {
                Button("Push (\(rowState.unpushedCommitCount))") {
                    if let path = store.activeRepositoryPath {
                        store.send(.stagingButtonTapped(repositoryPath: path))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button("Staging") {
                if let path = store.activeRepositoryPath {
                    store.send(.stagingButtonTapped(repositoryPath: path))
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
                ForEach(Array(repoSessions.prefix(9).enumerated()), id: \.offset) { index, session in
                    let key = KeyEquivalent(Character(String(index + 1)))
                    Button("") { onSelectTab(session.id) }
                        .keyboardShortcut(key, modifiers: .command)
                        .hidden()
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .background(Color(NSColor.windowBackgroundColor))
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

    // MARK: - Terminal Content

    // A single NSView container hosts all terminal sessions as direct subviews
    // and shows/hides them via isHidden. This keeps every LocalProcessTerminalView
    // in a stable position in the view hierarchy across repo switches and
    // hide/show cycles, preventing the zero-frame setFrameSize that would
    // send a spurious SIGWINCH and cause zsh to clear visible terminal output.
    @ViewBuilder
    private var terminalContent: some View {
        ZStack {
            TerminalContainerRepresentable(
                terminalViewStore: terminalViewStore,
                sessions: sessions,
                activeSessionId: activeSessionId,
                onStatusChange: onStatusChange
            )

            if let activeId = activeSessionId,
               let session = sessions[id: activeId],
               case let .failed(message) = session.status {
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
