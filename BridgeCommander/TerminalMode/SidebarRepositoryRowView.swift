// BridgeCommander/TerminalMode/SidebarRepositoryRowView.swift
import ComposableArchitecture
import SwiftUI

struct SidebarRepositoryRowView: View {
    let rowState: RepositoryRowReducer.State
    let isActive: Bool
    let hasTerminalSession: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                // Terminal-active indicator dot
                Circle()
                    .fill(hasTerminalSession ? Color.green : Color.clear)
                    .frame(width: 6, height: 6)

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
    }
}
