//
//  RepositoryActions.swift
//  Bridge Commander
//
//  Action buttons component for repository operations
//

import SwiftUI

struct RepositoryActions: View {
    let repository: Repository

    var body: some View {
        HStack(spacing: 12) {
            // Copy path button
            ActionButton(
                icon: "doc.on.doc",
                tooltip: "Copy path to clipboard",
                action: { copyToClipboard(repository.path) }
            )

            // Open in Finder button
            ActionButton(
                icon: "folder",
                tooltip: "Open in Finder",
                action: { openInFinder(repository.path) }
            )

            // Open Ticket button (conditional)
            if let ticketId = repository.ticketId {
                Button(action: {
                    openTicket(ticketId)
                }) {
                    Label("Ticket", systemImage: "ticket")
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help("Open YouTrack ticket \(ticketId)")
            }

            // Open in Android Studio button
            Button(action: {
                AndroidStudioLauncher.openInAndroidStudio(at: repository.path)
            }) {
                Label("Android Studio", systemImage: "hammer")
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .help("Open repository in Android Studio")

            // Open in Terminal button
            Button(action: {
                TerminalLauncher.openTerminal(at: repository.path)
            }) {
                Label("Terminal", systemImage: "terminal")
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)

            // Run Claude Code button
            Button(action: {
                ClaudeCodeLauncher.runClaudeCode(at: repository.path)
            }) {
                Label("Claude Code", systemImage: "wand.and.rays")
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .help("Open Terminal and run 'claude code .'")
        }
    }

    // MARK: - Helper Methods

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func openInFinder(_ path: String) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
    }

    private func openTicket(_ ticketId: String) {
        let urlString = "https://youtrack.livesport.eu/issue/\(ticketId)"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Icon Action Button Component

private struct ActionButton: View {
    let icon: String
    let tooltip: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }
}

#Preview {
    RepositoryActions(
        repository: Repository(
            name: "my-project",
            path: "/Users/username/projects/my-project",
            isWorktree: false,
            branchName: "feature/tech-60_error_service_MOB-1456"
        )
    )
    .padding()
}
