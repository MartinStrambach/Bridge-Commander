//
//  RepositoryInfo.swift
//  Bridge Commander
//
//  Information display component for repository details
//

import SwiftUI

struct RepositoryInfo: View {
    let repository: Repository

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Name and badges row
			HStack(spacing: 8) {
				if let formattedBranch = repository.formattedBranchName {
					Text(formattedBranch)
						.font(.headline)
				} else {
					Text(repository.name)
						.font(.headline)
				}

                if repository.isWorktree {
                    BadgeView(text: "WORKTREE", color: .blue)
                }

                if let ticketId = repository.ticketId {
                    BadgeView(text: ticketId, color: .orange)
                }
            }

            // Branch name
            branchView

            // Path
            Text(repository.path)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    @ViewBuilder
    private var branchView: some View {
        if let branchName = repository.branchName {
            // Branch exists but formatted to empty (detached HEAD, etc.)
            HStack(spacing: 4) {
                Image(systemName: "arrow.branch")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(branchName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            }
        } else {
            Text("Youtrack ticket: unknown")
                .font(.caption)
                .foregroundColor(.secondary)
                .italic()
        }
    }
}

// MARK: - Badge View Component

private struct BadgeView: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(4)
    }
}

#Preview {
    VStack(spacing: 20) {
        RepositoryInfo(
            repository: Repository(
                name: "my-project",
                path: "/Users/username/projects/my-project",
                isWorktree: false,
                branchName: "feature/tech-60_error_service_MOB-1456"
            )
        )

        RepositoryInfo(
            repository: Repository(
                name: "feature-branch",
                path: "/Users/username/projects/my-project-feature",
                isWorktree: true,
                branchName: "fix/mob-45_button_fix_MOB-2000"
            )
        )
    }
    .frame(width: 400)
    .padding()
}
