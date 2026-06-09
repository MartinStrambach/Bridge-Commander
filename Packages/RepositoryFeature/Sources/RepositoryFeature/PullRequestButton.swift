import AppUI
import GitHosting
import SwiftUI

/// Opens a pull/merge request in the browser, with a provider-aware icon
/// (GitHub vs GitLab) and a state-aware color and tooltip.
///
/// Shared by `RepositoryRowView` and the terminal header (`TerminalPanelView`)
/// so both present the PR button identically.
struct PullRequestButton: View {
	let url: URL
	let provider: PullRequestProvider?
	let state: PullRequestState?

	var body: some View {
		ActionButton(
			icon: icon,
			tooltip: tooltip,
			color: color
		) {
			NSWorkspace.shared.open(url)
		}
	}

	private var icon: ActionButton.ButtonIcon {
		switch provider {
		case .gitlab:
			.customImage("gitlab")
		case .github:
			.customImage("github")
		case .none:
			.systemImage(systemImageName)
		}
	}

	private var systemImageName: String {
		switch state {
		case .draft:
			"arrow.triangle.pull"
		case .merged:
			"arrow.triangle.merge"
		case .closed:
			"xmark.circle"
		case .none,
		     .ready:
			"arrow.triangle.pull"
		}
	}

	private var tooltip: String {
		let providerName = provider == .gitlab ? "GitLab" : "GitHub"
		let noun = provider == .gitlab ? "merge request" : "pull request"
		switch state {
		case .draft:
			return "Open draft \(noun) in \(providerName)"
		case .merged:
			return "Open merged \(noun) in \(providerName)"
		case .closed:
			return "Open closed \(noun) in \(providerName)"
		case .none,
		     .ready:
			return "Open \(noun) in \(providerName)"
		}
	}

	private var color: Color? {
		switch state {
		case .draft:
			.orange
		case .merged:
			.purple
		case .closed:
			.gray
		case .ready:
			.green
		case .none:
			nil
		}
	}
}
