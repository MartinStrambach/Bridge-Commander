// BridgeCommander/TerminalMode/SidebarRepositoryRowView.swift
import ComposableArchitecture
import SwiftUI

struct SidebarRepositoryRowView: View {
    let rowState: RepositoryRowReducer.State
    let isActive: Bool
    let sessionStatus: TerminalSessionStatus?
    let onTap: () -> Void
    var onKill: (() -> Void)? = nil
    @State private var showKillConfirmation = false

    var hasTerminalSession: Bool { sessionStatus != nil }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                // Terminal-active indicator dot
                TerminalStatusDotView(status: sessionStatus)

                VStack(alignment: .leading, spacing: 2) {
                    Text(rowState.formattedBranchName)
                        .font(.caption)
                        .fontWeight(isActive ? .semibold : .regular)
                        .lineLimit(1)
                        .foregroundColor(isActive ? .primary : .secondary)

                    Text(rowState.name)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Change count badges
                HStack(spacing: 4) {
                    if rowState.stagedChangesCount > 0 {
                        Text("\(rowState.stagedChangesCount)")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                    if rowState.unstagedChangesCount > 0 {
                        Text("\(rowState.unstagedChangesCount)")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                    if rowState.unpushedCommitCount > 0 {
                        Text("\(rowState.unpushedCommitCount)")
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
            .cornerRadius(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if hasTerminalSession, onKill != nil {
                Button("Kill Terminal", role: .destructive) {
                    showKillConfirmation = true
                }
            }
        }
        .confirmationDialog("Kill Terminal?", isPresented: $showKillConfirmation) {
            if let onKill {
                Button("Kill Terminal", role: .destructive, action: onKill)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will terminate the terminal session for \"\(rowState.name)\".")
        }
    }
}
