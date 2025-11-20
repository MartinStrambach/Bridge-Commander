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

                if repository.isMergeInProgress {
                    BadgeView(text: "MERGING", color: .red)
                }

                if repository.isWorktree {
                    BadgeView(text: "WORKTREE", color: .blue)
                }

                if let ticketId = repository.ticketId {
                    Button(action: {
                        openTicket(ticketId)
                    }) {
                        BadgeView(text: ticketId, color: .orange)
                    }
                    .buttonStyle(.plain)
                    .help("Open YouTrack ticket \(ticketId)")
                }

                // Unstaged changes badge
                if repository.unstagedChangesCount > 0 {
                    BadgeView(text: "\(repository.unstagedChangesCount) changes", color: .yellow)
                }

                // Staged changes badge
                if repository.stagedChangesCount > 0 {
                    BadgeView(text: "\(repository.stagedChangesCount) staged", color: .green)
                }
            }

            // Branch name
            branchView

            // Code review fields
            codeReviewView

            // Path
            Text(repository.path)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    // MARK: - Helper Methods

    private func openTicket(_ ticketId: String) {
        let urlString = "https://youtrack.livesport.eu/issue/\(ticketId)"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
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

    @ViewBuilder
    private var codeReviewView: some View {
        let hasAndroidCR = repository.androidCR != nil
        let hasIosCR = repository.iosCR != nil
        let hasAndroidReviewer = repository.androidReviewerName != nil
        let hasIosReviewer = repository.iosReviewerName != nil

        if hasAndroidCR || hasIosCR || hasAndroidReviewer || hasIosReviewer {
            VStack(alignment: .leading, spacing: 6) {
                // Android CR section
                if hasAndroidCR || hasAndroidReviewer {
                    HStack(spacing: 8) {
                        if let androidCR = repository.androidCR {
                            Button(action: {
								if let url = URL(string: repository.prUrl ?? "") {
                                    NSWorkspace.shared.open(url)
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "link")
                                        .font(.caption2)
                                    Text("Android CR: \(repository.androidCR ?? "")")
                                        .font(.caption2)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.2))
                                .foregroundColor(.blue)
                                .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                            .help("Open Android code review")
                        }

                        if let androidReviewerName = repository.androidReviewerName {
                            HStack(spacing: 4) {
                                Image(systemName: "person.fill")
                                    .font(.caption2)
                                Text(androidReviewerName)
                                    .font(.caption2)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.15))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                        }
                    }
                }

                // iOS CR section
                if hasIosCR || hasIosReviewer {
                    HStack(spacing: 8) {
                        if let iosCR = repository.iosCR {
                            Button(action: {
								if let url = URL(string: repository.prUrl ?? "") {
                                    NSWorkspace.shared.open(url)
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "link")
                                        .font(.caption2)
                                    Text("iOS CR: \(repository.iosCR ?? "")")
                                        .font(.caption2)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.purple.opacity(0.2))
                                .foregroundColor(.purple)
                                .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                            .help("Open iOS code review")
                        }

                        if let iosReviewerName = repository.iosReviewerName {
                            HStack(spacing: 4) {
                                Image(systemName: "person.fill")
                                    .font(.caption2)
                                Text(iosReviewerName)
                                    .font(.caption2)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.15))
                            .foregroundColor(.purple)
                            .cornerRadius(4)
                        }
                    }
                }
            }
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
