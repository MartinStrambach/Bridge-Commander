import GitHosting
import SwiftUI

/// Shows the number of unresolved review discussions on the branch's MR/PR and
/// opens it in the browser when clicked.
///
/// Shared by `RepositoryRowView` and the terminal header (`TerminalPanelView`)
/// so both present the count identically. Callers hide it when the count is zero.
struct UnresolvedDiscussionsBadge: View {
	let count: Int
	let url: URL
	let provider: PullRequestProvider?

	var body: some View {
		Button {
			NSWorkspace.shared.open(url)
		} label: {
			HStack(spacing: 3) {
				Image(systemName: "bubble.left.and.bubble.right.fill")
					.font(.caption2)
				Text("\(count)")
					.font(.caption)
					.lineLimit(1)
			}
			.foregroundColor(.orange)
			.padding(.horizontal, 6)
			.padding(.vertical, 2)
			// Stretch the pill to whatever width the enclosing VStack settles on,
			// so the badge always matches the PR button's width above it.
			.frame(maxWidth: .infinity)
			.background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
			.contentShape(RoundedRectangle(cornerRadius: 4))
		}
		.buttonStyle(.plain)
		.help(tooltip)
	}

	private var tooltip: String {
		let noun = provider == .gitlab ? "merge request" : "pull request"
		let discussions = count == 1 ? "1 unresolved discussion" : "\(count) unresolved discussions"
		return "\(discussions) — open \(noun)"
	}
}

#Preview {
	HStack(spacing: 8) {
		UnresolvedDiscussionsBadge(
			count: 1,
			url: URL(string: "https://gitlab.com")!,
			provider: .gitlab
		)
		UnresolvedDiscussionsBadge(
			count: 12,
			url: URL(string: "https://github.com")!,
			provider: .github
		)
	}
	.padding()
}
