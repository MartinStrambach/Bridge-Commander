import ActionButtons
import AppKit
import AppUI
import ComposableArchitecture
import GitActionsMenu
import GitHosting
import Settings
import SwiftUI
import YouTrackMenu

/// The row's "⋯" menu: the action bar items the user placed in it (Settings ▸ Repository Rows).
/// The row draws it only while it holds at least one.
extension RepositoryRowView {
	func moreActionsMenu(items: [RepositoryRowItem]) -> some View {
		PopUpMenuButton {
			for item in items {
				moreMenuEntries(item)
			}
		} label: {
			// The system font's size, as the pull-down's AppKit-drawn icon had: a `List` section
			// header (the repository group's row) would make it smaller.
			Image(systemName: "ellipsis.circle")
				.scaledFont(size: 13)
				.foregroundColor(.secondary)
		}
		.help("More actions")
	}

	/// An action bar item as menu entries. The menus become submenus; an item that does not apply
	/// to this repository adds nothing, as it draws nothing in the row.
	@PopUpMenuBuilder
	private func moreMenuEntries(_ item: RepositoryRowItem) -> [PopUpMenuEntry] {
		switch item {
		case .gitActions:
			store.scope(\.gitActionsMenu, action: \.gitActionsMenu).submenuEntry

		case .tuist:
			if store.supportsIOS, store.supportsTuist {
				store.scope(\.tuistButton, action: \.tuistButton).submenuEntry
			}

		case .youTrackMenu:
			if let youtrackButtonStore = store.scope(\.youtrackButton, action: \.youtrackButton) {
				youtrackButtonStore.submenuEntry
			}

		case .copyPath:
			PopUpMenuAction("Copy Path", systemImage: "doc.on.doc") {
				copyToClipboard(store.path)
			}

		case .showInFinder:
			PopUpMenuAction("Show in Finder", systemImage: "folder") {
				openInFinder(store.path)
			}

		case .share:
			PopUpMenuEntry.share(title: "Share Branch, Ticket and PR…", text: store.shareButton.shareText)

		case .pullRequest:
			if let prFetchError = store.prFetchError {
				PopUpMenuAction(
					"Pull Request Lookup Failed",
					systemImage: "exclamationmark.triangle.fill",
					isEnabled: false,
					help: prFetchError
				) {}
			}
			if let prUrl = store.prUrl, let url = URL(string: prUrl) {
				PopUpMenuAction(
					PullRequestButton(url: url, provider: store.prProvider, state: store.prState).tooltip
						+ unresolvedDiscussionsSuffix,
					systemImage: "arrow.triangle.pull"
				) {
					NSWorkspace.shared.open(url)
				}
			}

		case .pipeline:
			if let pipelineUrl = store.pipelineUrl,
			   let url = URL(string: pipelineUrl),
			   let pipelineState = store.pipelineState {
				PopUpMenuAction(
					PipelineStatusButton(url: url, state: pipelineState, hasConflicts: store.prHasConflicts).tooltip,
					systemImage: pipelineState.systemImageName(hasConflicts: store.prHasConflicts)
				) {
					NSWorkspace.shared.open(url)
				}
			}

		case .approval:
			if let slot = store.approvalSlot,
			   let prUrl = store.prUrl,
			   let url = URL(string: prUrl) {
				switch slot {
				case .draft:
					PopUpMenuAction("Draft — Not Ready for Review", systemImage: "pencil.and.outline") {
						NSWorkspace.shared.open(url)
					}
				case let .review(status):
					PopUpMenuAction(
						"Review: \(ApprovalStatusButton(url: url, status: status, provider: store.prProvider).headline)",
						systemImage: status.decision.systemImageName
					) {
						NSWorkspace.shared.open(url)
					}
				}
			}

		case .ticket:
			if let ticketButtonStore = store.scope(\.ticketButton, action: \.ticketButton) {
				PopUpMenuAction("Open YouTrack Ticket \(ticketButtonStore.ticketId)", systemImage: "ticket") {
					ticketButtonStore.send(.openTicketButtonTapped)
				}
			}
			else if store.showsMissingYouTrackURLWarning {
				PopUpMenuAction(
					"Set a YouTrack URL for \(store.ticketId ?? "the Ticket")…",
					systemImage: "exclamationmark.triangle.fill"
				) {
					openSettings()
				}
			}

		case .web:
			if let webButtonStore = store.scope(\.webButton, action: \.webButton) {
				PopUpMenuAction("Open Web Preview", systemImage: "globe") {
					webButtonStore.send(.openWebButtonTapped)
				}
			}

		case .terminal:
			PopUpMenuAction("Open in Terminal", systemImage: "terminal") {
				store.send(.terminalButton(.openTerminalButtonTapped))
			}

		case .androidStudio:
			if store.supportsAndroid {
				store.scope(\.androidStudioButton, action: \.androidStudioButton).menuEntry
			}

		case .xcode:
			if store.supportsIOS {
				store.scope(\.xcodeButton, action: \.xcodeButton).menuEntry
			}

		case .claudeCode:
			store.scope(\.claudeCodeButton, action: \.claudeCodeButton).menuEntry
		}
	}

	/// What a menu entry's own view would present, attached outside the menu. Items with nothing
	/// to present draw nothing.
	@ViewBuilder
	func moreMenuPresenter(_ item: RepositoryRowItem) -> some View {
		switch item {
		case .gitActions:
			Color.clear
				.gitActionsMenuPresentations(store: store.scope(\.gitActionsMenu, action: \.gitActionsMenu))

		case .tuist:
			if store.supportsIOS, store.supportsTuist {
				Color.clear
					.tuistPresentations(store: store.scope(\.tuistButton, action: \.tuistButton))
			}

		case .youTrackMenu:
			if let youtrackButtonStore = store.scope(\.youtrackButton, action: \.youtrackButton) {
				Color.clear
					.youTrackMenuPresentations(store: youtrackButtonStore)
			}

		case .androidStudio:
			if store.supportsAndroid {
				Color.clear
					.androidStudioPresentations(store: store.scope(\.androidStudioButton, action: \.androidStudioButton))
			}

		case .xcode:
			if store.supportsIOS {
				Color.clear
					.xcodeProjectPresentations(store: store.scope(\.xcodeButton, action: \.xcodeButton))
			}

		case .claudeCode:
			Color.clear
				.claudeCodePresentations(store: store.scope(\.claudeCodeButton, action: \.claudeCodeButton))

		case .copyPath, .showInFinder, .share, .pullRequest, .pipeline, .approval, .ticket, .web, .terminal:
			EmptyView()
		}
	}

	private var unresolvedDiscussionsSuffix: String {
		guard let count = store.prUnresolvedDiscussions, count > 0 else {
			return ""
		}
		return count == 1 ? " · 1 unresolved discussion" : " · \(count) unresolved discussions"
	}

	func copyToClipboard(_ text: String) {
		let pasteboard = NSPasteboard.general
		pasteboard.clearContents()
		pasteboard.setString(text, forType: .string)
	}

	func openInFinder(_ path: String) {
		NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
	}
}
