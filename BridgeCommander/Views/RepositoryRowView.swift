//
//  RepositoryRowView.swift
//  Bridge Commander
//
//  View component for displaying a single repository row
//

import SwiftUI

struct RepositoryRowView: View {
    let repository: Repository
    let onRemove: (() -> Void)?

    init(repository: Repository, onRemove: (() -> Void)? = nil) {
        self.repository = repository
        self.onRemove = onRemove
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            RepositoryIcon(
                isWorktree: repository.isWorktree,
                isMergeInProgress: repository.isMergeInProgress
            )
            RepositoryInfo(repository: repository)
            Spacer()
            RepositoryActions(repository: repository, onRemoveWorktree: onRemove)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .contentShape(Rectangle())
    }
}

#Preview {
    VStack(spacing: 0) {
        RepositoryRowView(
            repository: Repository(
                name: "my-project",
                path: "/Users/username/projects/my-project",
                isWorktree: false
            )
        )

        Divider()

        RepositoryRowView(
            repository: Repository(
                name: "feature-branch",
                path: "/Users/username/projects/my-project-feature",
                isWorktree: true
            )
        )
    }
    .frame(width: 600)
}
