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
				}
				else {
					Text(repository.name)
						.font(.headline)
				}

				if repository.isMergeInProgress {
					BadgeView(text: "MERGING", color: .red)
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
		}
		else {
			Text("Youtrack ticket: unknown")
				.font(.caption)
				.foregroundColor(.secondary)
				.italic()
		}
	}

	@ViewBuilder
	private var codeReviewView: some View {
		VStack(alignment: .leading, spacing: 6) {
			CodeReviewSection(
				platform: "Android",
				state: repository.androidCR,
				reviewerName: repository.androidReviewerName,
				prUrl: repository.prUrl
			)

			CodeReviewSection(
				platform: "iOS",
				state: repository.iosCR,
				reviewerName: repository.iosReviewerName,
				prUrl: repository.prUrl
			)
		}
	}

	// MARK: - Helper Methods

	private func openTicket(_ ticketId: String) {
		let urlString = "https://youtrack.livesport.eu/issue/\(ticketId)"
		if let url = URL(string: urlString) {
			NSWorkspace.shared.open(url)
		}
	}

}

// MARK: - Code Review Section Component

private struct CodeReviewSection: View {
	let platform: String
	let state: String?
	let reviewerName: String?
	let prUrl: String?

	private var stateColor: Color {
		guard let state else {
			return .primary
		}

		if state.lowercased() == "passed" || state.lowercased() == "n/a" {
			return .gray
		}
		else {
			return Color(.sRGB, red: 1.0, green: 0.4, blue: 0.4)
		}
	}

	var body: some View {
		if state != nil || reviewerName != nil {
			HStack(spacing: 8) {
				if let state {
					CodeReviewBadge(
						platform: platform,
						state: state,
						prUrl: prUrl,
						color: stateColor
					)
				}

				if let reviewerName {
					ReviewerBadge(
						name: reviewerName,
						color: stateColor,
						image: Image(systemName: "person.fill")
					)
				}
			}
		}
	}
}

// MARK: - Code Review Badge Component

private struct CodeReviewBadge: View {
	let platform: String
	let state: String?
	let prUrl: String?
	let color: Color

	var body: some View {
		Button {
			if let url = URL(string: prUrl ?? "") {
				NSWorkspace.shared.open(url)
			}
		} label: {
			ReviewerBadge(name: "\(platform) CR: \(state ?? "")", color: color, image: Image(systemName: "link"))
		}
		.buttonStyle(.plain)
		.help("Open \(platform) code review")
	}
}

// MARK: - Reviewer Badge Component

private struct ReviewerBadge: View {
	let name: String
	let color: Color
	let image: Image

	var body: some View {
		HStack(spacing: 4) {
			image
				.font(.caption2)
			Text(name)
				.font(.caption2)
		}
		.padding(.horizontal, 6)
		.padding(.vertical, 2)
		.background(color.opacity(0.15))
		.foregroundColor(color)
		.cornerRadius(4)
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
