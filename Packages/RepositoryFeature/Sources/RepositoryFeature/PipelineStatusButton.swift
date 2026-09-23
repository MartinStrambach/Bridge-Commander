import AppUI
import GitHosting
import SwiftUI

/// Opens a GitLab merge-request pipeline in the browser, with a status-aware icon and color.
/// Mirrors `PullRequestButton`: the SF Symbol name comes from `PipelineState.systemImageName`
/// (in GitHosting, unit-tested); color and tooltip are SwiftUI-only and live here.
///
/// A conflict with the target branch turns a passing pipeline yellow with a warning
/// icon: green would say "ready to merge" about an MR that cannot merge.
struct PipelineStatusButton: View {
	let url: URL
	let state: PipelineState
	var hasConflicts = false

	var body: some View {
		ActionButton(
			icon: .systemImage(state.systemImageName(hasConflicts: hasConflicts)),
			tooltip: tooltip,
			color: color
		) {
			NSWorkspace.shared.open(url)
		}
	}

	private var tooltip: String {
		let conflicts = hasConflicts ? " · conflicts with target branch" : ""
		return "Pipeline: \(state.rawValue)\(conflicts) — open in GitLab"
	}

	private var color: Color {
		if hasConflicts, state == .success {
			return .yellow
		}
		return switch state {
		case .success:
			.green
		case .failed:
			.red
		case .running:
			.blue
		case .pending,
		     .created,
		     .preparing,
		     .waitingForResource,
		     .scheduled:
			.orange
		case .canceled,
		     .skipped,
		     .manual:
			.gray
		}
	}
}
