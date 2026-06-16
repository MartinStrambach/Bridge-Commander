import AppUI
import GitHosting
import SwiftUI

/// Opens a GitLab merge-request pipeline in the browser, with a status-aware icon and color.
/// Mirrors `PullRequestButton`: the SF Symbol name comes from `PipelineState.systemImageName`
/// (in GitHosting, unit-tested); color and tooltip are SwiftUI-only and live here.
struct PipelineStatusButton: View {
	let url: URL
	let state: PipelineState

	var body: some View {
		ActionButton(
			icon: .systemImage(state.systemImageName),
			tooltip: tooltip,
			color: color
		) {
			NSWorkspace.shared.open(url)
		}
	}

	private var tooltip: String {
		"Pipeline: \(state.rawValue) — open in GitLab"
	}

	private var color: Color {
		switch state {
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
