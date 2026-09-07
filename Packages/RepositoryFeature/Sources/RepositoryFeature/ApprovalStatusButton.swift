import AppUI
import GitHosting
import SwiftUI

/// What the action bar's approval slot should render. Resolved by
/// `RepositoryRowReducer.State.approvalSlot` so the row and the terminal header
/// cannot disagree about it.
enum ApprovalSlot: Equatable {
	/// The PR is a draft — show that instead of review state.
	case draft
	case review(ApprovalStatus)
}

/// Opens a PR/MR at its review state, with a decision-aware icon and color.
/// Mirrors `PipelineStatusButton`: the SF Symbol name comes from
/// `ApprovalDecision.systemImageName` (in GitHosting, unit-tested); color and
/// tooltip are SwiftUI-only and live here.
struct ApprovalStatusButton: View {
	let url: URL
	let status: ApprovalStatus
	let provider: PullRequestProvider?

	var body: some View {
		ActionButton(
			icon: .systemImage(status.decision.systemImageName),
			tooltip: tooltip,
			color: color
		) {
			NSWorkspace.shared.open(url)
		}
	}

	private var color: Color {
		switch status.decision {
		case .approved:
			.green
		case .changesRequested:
			.red
		// Missing approvals are treated as needing attention rather than as a quiet
		// resting state: a ready MR short of its approvals is blocked, and orange is
		// what the rest of the row uses for "this wants action" (no remote, draft,
		// failed PR fetch).
		case .reviewRequired:
			.orange
		}
	}

	private var tooltip: String {
		let noun = provider == .gitlab ? "merge request" : "pull request"
		let names = status.decision == .changesRequested
			? status.changesRequestedBy
			: status.approvedBy

		return "\(headline) — open \(noun)" + namesSuffix(names)
	}

	private var headline: String {
		switch status.decision {
		// Deliberately no fraction here even when a count is available: the provider
		// already says every rule is satisfied, and a partial-looking "6 of 8" next
		// to a green check reads as a contradiction.
		case .approved:
			"Approved"
		case .changesRequested:
			"Changes requested"
		case .reviewRequired:
			if let satisfied = status.approvalsSatisfied, let required = status.approvalsRequired {
				"Awaiting review (\(satisfied) of \(required))"
			}
			else {
				"Awaiting review"
			}
		}
	}

	private func namesSuffix(_ reviewers: [Reviewer]) -> String {
		guard !reviewers.isEmpty else {
			return ""
		}
		return "\n" + reviewers.map(\.displayName).joined(separator: ", ")
	}
}

/// The draft counterpart of `ApprovalStatusButton`, holding the same slot so the
/// action bar keeps a stable width as a PR moves from draft to ready.
struct DraftStatusButton: View {
	let url: URL
	let provider: PullRequestProvider?

	var body: some View {
		ActionButton(
			icon: .systemImage("pencil.and.outline"),
			tooltip: "Draft \(provider == .gitlab ? "merge request" : "pull request") — not ready for review",
			color: .orange
		) {
			NSWorkspace.shared.open(url)
		}
	}
}
