import GitHosting
import SwiftUI

/// The action bar's approval slot: a decision icon plus the faces behind it, or a
/// draft marker when the PR is not up for review yet.
///
/// Shared by `RepositoryRowView` and the terminal header (`TerminalPanelView`) so
/// both present review state identically. What to show is decided upstream by
/// `RepositoryRowReducer.State.approvalSlot`; this only draws it.
struct ApprovalSlotView: View {
	let slot: ApprovalSlot
	let url: URL
	let provider: PullRequestProvider?

	var body: some View {
		// Stacked rather than side by side, matching the PR button with its
		// unresolved-discussions badge beneath it.
		VStack(alignment: .center, spacing: 2) {
			switch slot {
			case .draft:
				DraftStatusButton(url: url, provider: provider)

			case let .review(status):
				ApprovalStatusButton(url: url, status: status, provider: provider)
				let faces = Self.faces(for: status)
				if !faces.isEmpty {
					ApproverAvatarStack(reviewers: faces)
				}
			}
		}
		// The action bar can be narrower than its ideal width (narrow sidebar pane);
		// without this the avatars get compressed into slivers.
		.fixedSize(horizontal: true, vertical: false)
	}

	/// Whoever is responsible for the current decision: the blockers when changes
	/// are requested, otherwise whoever has signed off so far — including partial
	/// approvals on a PR that still needs more.
	private static func faces(for status: ApprovalStatus) -> [Reviewer] {
		status.decision == .changesRequested
			? status.changesRequestedBy
			: status.approvedBy
	}
}
