// BridgeCommander/TerminalMode/TerminalPanelView.swift
import ComposableArchitecture
import SwiftUI
import SwiftTerm

struct TerminalPanelView: View {
    @Bindable var store: StoreOf<TerminalLayoutReducer>
    let activeRowState: RepositoryRowReducer.State?
    let terminalViewStore: TerminalViewStore
    let sessions: IdentifiedArrayOf<TerminalSession>
    let onStatusChange: @Sendable (String, TerminalSessionStatus) -> Void
    let onRetry: (String) -> Void
    let onKill: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
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

            Button(action: onKill) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Kill terminal")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
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
                activeRepositoryPath: store.activeRepositoryPath,
                onStatusChange: onStatusChange
            )

            if let activePath = store.activeRepositoryPath,
               let session = sessions[id: activePath],
               case let .failed(message) = session.status {
                terminalErrorView(message: message, repositoryPath: activePath)
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

    private func terminalErrorView(message: String, repositoryPath: String) -> some View {
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
                onRetry(repositoryPath)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
    }
}
