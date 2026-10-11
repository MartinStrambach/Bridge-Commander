import ActionButtons
import AppKit
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
		Menu {
			Group {
				ForEach(items) { item in
					moreMenuItem(item)
				}
			}
			.labelStyle(.titleAndIcon)
		} label: {
			Image(systemName: "ellipsis.circle")
		}
		.menuStyle(.borderlessButton)
		.menuIndicator(.hidden)
		.fixedSize()
		.foregroundColor(.secondary)
		.help("More actions")
	}

	/// An action bar item as a menu entry. The menus become submenus; an item that does not apply
	/// to this repository draws nothing, as it does in the row.
	@ViewBuilder
	private func moreMenuItem(_ item: RepositoryRowItem) -> some View {
		switch item {
		case .gitActions:
			GitActionsSubmenu(store: store.scope(\.gitActionsMenu, action: \.gitActionsMenu))

		case .tuist:
			if store.supportsIOS, store.supportsTuist {
				TuistSubmenu(store: store.scope(\.tuistButton, action: \.tuistButton))
			}

		case .youTrackMenu:
			if let youtrackButtonStore = store.scope(\.youtrackButton, action: \.youtrackButton) {
				YouTrackSubmenu(store: youtrackButtonStore)
			}

		case .copyPath:
			Button {
				copyToClipboard(store.path)
			} label: {
				Label("Copy Path", systemImage: "doc.on.doc")
			}

		case .showInFinder:
			Button {
				openInFinder(store.path)
			} label: {
				Label("Show in Finder", systemImage: "folder")
			}

		case .share:
			ShareButtonView(store: store.scope(\.shareButton, action: \.shareButton), style: .menuItem)

		case .pullRequest:
			if let prFetchError = store.prFetchError {
				Button {} label: {
					Label("Pull Request Lookup Failed", systemImage: "exclamationmark.triangle.fill")
				}
				.disabled(true)
				.help(prFetchError)
			}
			if let prUrl = store.prUrl, let url = URL(string: prUrl) {
				Button {
					NSWorkspace.shared.open(url)
				} label: {
					Label(
						PullRequestButton(url: url, provider: store.prProvider, state: store.prState).tooltip
							+ unresolvedDiscussionsSuffix,
						systemImage: "arrow.triangle.pull"
					)
				}
			}

		case .pipeline:
			if let pipelineUrl = store.pipelineUrl,
			   let url = URL(string: pipelineUrl),
			   let pipelineState = store.pipelineState {
				Button {
					NSWorkspace.shared.open(url)
				} label: {
					Label(
						PipelineStatusButton(url: url, state: pipelineState, hasConflicts: store.prHasConflicts).tooltip,
						systemImage: pipelineState.systemImageName(hasConflicts: store.prHasConflicts)
					)
				}
			}

		case .approval:
			if let slot = store.approvalSlot,
			   let prUrl = store.prUrl,
			   let url = URL(string: prUrl) {
				Button {
					NSWorkspace.shared.open(url)
				} label: {
					switch slot {
					case .draft:
						Label("Draft — Not Ready for Review", systemImage: "pencil.and.outline")
					case let .review(status):
						Label(
							"Review: \(ApprovalStatusButton(url: url, status: status, provider: store.prProvider).headline)",
							systemImage: status.decision.systemImageName
						)
					}
				}
			}

		case .ticket:
			if let ticketButtonStore = store.scope(\.ticketButton, action: \.ticketButton) {
				Button {
					ticketButtonStore.send(.openTicketButtonTapped)
				} label: {
					Label("Open YouTrack Ticket \(ticketButtonStore.ticketId)", systemImage: "ticket")
				}
			}
			else if store.showsMissingYouTrackURLWarning {
				Button {
					openSettings()
				} label: {
					Label("Set a YouTrack URL for \(store.ticketId ?? "the Ticket")…", systemImage: "exclamationmark.triangle.fill")
				}
			}

		case .web:
			if let webButtonStore = store.scope(\.webButton, action: \.webButton) {
				Button {
					webButtonStore.send(.openWebButtonTapped)
				} label: {
					Label("Open Web Preview", systemImage: "globe")
				}
			}

		case .terminal:
			Button {
				store.send(.terminalButton(.openTerminalButtonTapped))
			} label: {
				Label("Open in Terminal", systemImage: "terminal")
			}

		case .androidStudio:
			if store.supportsAndroid {
				AndroidStudioMenuItem(store: store.scope(\.androidStudioButton, action: \.androidStudioButton))
			}

		case .xcode:
			if store.supportsIOS {
				XcodeProjectMenuItem(store: store.scope(\.xcodeButton, action: \.xcodeButton))
			}

		case .claudeCode:
			ClaudeCodeMenuItem(store: store.scope(\.claudeCodeButton, action: \.claudeCodeButton))
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
