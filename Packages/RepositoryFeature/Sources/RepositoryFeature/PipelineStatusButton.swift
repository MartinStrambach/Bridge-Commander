import AppUI
import GitHosting
import SwiftUI

/// Opens a GitLab merge-request pipeline in the browser, with a status-aware icon and color.
/// Mirrors `PullRequestButton`: the SF Symbol name comes from `PipelineState.systemImageName`
/// (in GitHosting, unit-tested); color and tooltip are SwiftUI-only and live here.
///
/// A conflict with the target branch turns a passing pipeline yellow with a warning
/// icon: green would say "ready to merge" about an MR that cannot merge.
///
/// A merge train pipeline still in progress shows a tram instead of the running/clock
/// icon, and the tooltip names it and the MR's place on the train.
struct PipelineStatusButton: View {
	let url: URL
	let state: PipelineState
	var isMergeTrain = false
	var mergeTrain: MergeTrainStatus?
	var hasConflicts = false

	var body: some View {
		ActionButton(
			icon: .systemImage(systemImageName),
			tooltip: tooltip,
			color: color
		) {
			NSWorkspace.shared.open(url)
		}
	}

	var systemImageName: String {
		state.systemImageName(hasConflicts: hasConflicts, isMergeTrain: isMergeTrain)
	}

	var tooltip: String {
		let name = isMergeTrain ? "Merge train pipeline" : "Pipeline"
		let train = mergeTrain.map { " · \($0.summary)" } ?? ""
		let conflicts = hasConflicts ? " · conflicts with target branch" : ""
		return "\(name): \(state.rawValue)\(train)\(conflicts) — open in GitLab"
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
