//
//  RepositoryActions.swift
//  Bridge Commander
//
//  Action buttons component for repository operations
//

import SwiftUI

struct RepositoryActions: View {
    let repository: Repository
    let onRemoveWorktree: (() -> Void)?
    @EnvironmentObject var abbreviationMode: AbbreviationMode

    @State private var showRemoveConfirmation = false
    @State private var isRemoving = false
    @State private var removalError: String?

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
                    Label(abbreviationMode.isAbbreviated ? "Tkt" : "Ticket", systemImage: "ticket")
                        .frame(minWidth: abbreviationMode.isAbbreviated ? 50 : 100)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .fixedSize(horizontal: true, vertical: false)
                .help("Open YouTrack ticket \(ticketId)")
            }

            // Open in Android Studio button
            Button(action: {
                AndroidStudioLauncher.openInAndroidStudio(at: repository.path)
            }) {
                Label(abbreviationMode.isAbbreviated ? "AS" : "Android Studio", systemImage: "square.3.layers.3d.top.filled")
                    .frame(minWidth: abbreviationMode.isAbbreviated ? 50 : 100)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .fixedSize(horizontal: true, vertical: false)
            .help("Open repository in Android Studio")

            // Open in Terminal button
            Button(action: {
                TerminalLauncher.openTerminal(at: repository.path)
            }) {
                Label(abbreviationMode.isAbbreviated ? "Trm" : "Terminal", systemImage: "terminal")
                    .frame(minWidth: abbreviationMode.isAbbreviated ? 50 : 100)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .fixedSize(horizontal: true, vertical: false)

            // Open Xcode Project button
            XcodeProjectButton(repositoryPath: repository.path)

            // Run Claude Code button
            Button(action: {
                ClaudeCodeLauncher.runClaudeCode(at: repository.path)
            }) {
                Label(abbreviationMode.isAbbreviated ? "CC" : "Claude Code", systemImage: "wand.and.rays")
                    .frame(minWidth: abbreviationMode.isAbbreviated ? 50 : 100)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .fixedSize(horizontal: true, vertical: false)
            .help("Open Terminal and run 'claude code .'")

            // Remove worktree button (conditional)
            if repository.isWorktree {
                if isRemoving {
					ProgressView()
                } else {
                    Button(action: { showRemoveConfirmation = true }) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Remove worktree")
                    .padding(.leading, 20)
                }
            }
        }
        .alert("Remove Worktree", isPresented: $showRemoveConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) {
                removeWorktree()
            }
        } message: {
            Text("Are you sure you want to remove this worktree?\n\n\(repository.path)")
        }
        .alert("Removal Error", isPresented: .constant(removalError != nil)) {
            Button("OK") {
                removalError = nil
            }
        } message: {
            if let error = removalError {
                Text(error)
            }
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

    private func removeWorktree() {
        isRemoving = true
        DispatchQueue.global().async {
            do {
                try GitWorktreeRemover.removeWorktree(at: repository.path)
                DispatchQueue.main.async {
                    isRemoving = false
                    onRemoveWorktree?()
                }
            } catch {
                DispatchQueue.main.async {
                    isRemoving = false
                    removalError = error.localizedDescription
                }
            }
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
        ),
        onRemoveWorktree: nil
    )
    .padding()
}
