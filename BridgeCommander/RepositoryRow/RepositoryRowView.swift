import ComposableArchitecture
import SwiftUI

struct RepositoryRowView: View {
	let store: StoreOf<RepositoryRowReducer>
	@EnvironmentObject
	var abbreviationMode: AbbreviationMode

	var body: some View {
		HStack(alignment: .center, spacing: 16) {
			RepositoryIcon(
				isWorktree: store.isWorktree,
				isMergeInProgress: store.gitActionsMenu.isMergeInProgress
			)
			repositoryInfo
			Spacer()
			repositoryActions
		}
		.padding(.horizontal, 16)
		.padding(.vertical, 12)
		.background(backgroundColorForState)
		.contentShape(Rectangle())
		.task {
			store.send(.onAppear)
		}
	}

	// MARK: - Repository Info

	private var repositoryInfo: some View {
		VStack(alignment: .leading, spacing: 4) {
			HStack(spacing: 12) {
				VStack(alignment: .leading, spacing: 2) {
					Text(store.formattedBranchName)
						.font(.headline)
						.lineLimit(1)

					// Branch with icon
					if let branchName = store.branchName {
						HStack(spacing: 4) {
							Image(systemName: "arrow.trianglehead.branch")
								.font(.caption)
								.foregroundColor(.secondary)
							Text(branchName)
								.font(.caption)
								.foregroundColor(.secondary)
								.lineLimit(1)
								.truncationMode(.middle)
							changesIndicator
						}
					}
				}

				Spacer()
			}

			// Code review section
			if store.prUrl != nil || store.androidCR != nil || store.iosCR != nil {
				codeReviewSection
			}
		}
	}

	// MARK: - Changes Indicator

	private var changesIndicator: some View {
		HStack(spacing: 12) {
			// Staged changes
			if store.stagedChangesCount > 0 {
				HStack(spacing: 4) {
					Image(systemName: "checkmark.circle.fill")
						.foregroundColor(.green)
					Text("\(store.stagedChangesCount)")
						.font(.caption)
				}
			}

			// Unstaged changes
			if store.unstagedChangesCount > 0 {
				HStack(spacing: 4) {
					Image(systemName: "pencil.circle.fill")
						.foregroundColor(.orange)
					Text("\(store.unstagedChangesCount)")
						.font(.caption)
				}
			}

			// Unpushed commits
			if store.unpushedCommitCount > 0 {
				HStack(spacing: 4) {
					Image(systemName: "exclamationmark.circle.fill")
						.foregroundColor(.red)
					Text("\(store.unpushedCommitCount)")
						.font(.caption)
				}
			}

			// Merge in progress
			if store.gitActionsMenu.isMergeInProgress {
				HStack(spacing: 4) {
					Image(systemName: "arrow.triangle.merge")
						.foregroundColor(.red)
					Text("Merge")
						.font(.caption)
				}
			}
		}
	}

	// MARK: - Code Review Section

	private var codeReviewSection: some View {
		HStack(spacing: 8) {
			if let ticketId = store.ticketId {
				Text(ticketId)
					.font(.caption)
					.padding(6)
					.background(Color.blue.opacity(0.2))
					.cornerRadius(4)
					.lineLimit(1)
			}

			if let androidCR = store.androidCR {
				let waiting = androidCR == .passed || androidCR == .notApplicable || store
					.ticketState != .waitingToCodeReview
				HStack(spacing: 4) {
					Image("android")
						.resizable()
						.renderingMode(.template)
						.scaledToFit()
						.frame(height: 12)
						.foregroundColor(waiting ? .secondary : .orange.opacity(0.75))
					Text(androidCR.rawValue)
						.font(.caption)
						.foregroundColor(waiting ? .secondary : .orange.opacity(0.75))
						.lineLimit(1)
					if let reviewerName = store.androidReviewerName {
						Text("(\(reviewerName))")
							.font(.caption2)
							.foregroundColor(waiting ? .secondary : .orange)
							.lineLimit(1)
					}
				}
				.padding(6)
				.cornerRadius(4)
			}

			if let iosCR = store.iosCR {
				let waiting = iosCR == .passed || iosCR == .notApplicable || store.ticketState != .waitingToCodeReview
				HStack(spacing: 4) {
					Image(systemName: "apple.logo")
						.renderingMode(.template)
						.foregroundColor(waiting ? .secondary : .orange.opacity(0.75))
					Text(iosCR.rawValue)
						.font(.caption)
						.foregroundColor(waiting ? .secondary : .orange.opacity(0.75))
						.lineLimit(1)
					if let reviewerName = store.iosReviewerName {
						Text("(\(reviewerName))")
							.font(.caption2)
							.foregroundColor(waiting ? .secondary : .orange)
							.lineLimit(1)
					}
				}
				.padding(6)
				.cornerRadius(4)
			}
		}
	}

	// MARK: - Repository Actions

	private var repositoryActions: some View {
		HStack(spacing: 8) {
			// Git actions dropdown menu
			GitActionsMenuView(store: store.scope(
				state: \.gitActionsMenu,
				action: \.gitActionsMenu
			))

			TuistButtonView(store: store.scope(
				state: \.tuistButton,
				action: \.tuistButton
			))
			.environmentObject(abbreviationMode)

			// Copy path button
			ActionButton(
				icon: .systemImage("doc.on.doc"),
				tooltip: "Copy path to clipboard",
				action: { copyToClipboard(store.path) }
			)

			// Open in Finder button
			ActionButton(
				icon: .systemImage("folder"),
				tooltip: "Open in Finder",
				action: { openInFinder(store.path) }
			)

			// Open PR button (conditional)
			if let prUrl = store.prUrl {
				ActionButton(
					icon: .customImage("gitlab"),
					tooltip: "Open pull request in Gitlab"
				) {
					if let url = URL(string: prUrl) {
						NSWorkspace.shared.open(url)
					}
				}
			}

			ShareButtonView(store: store.scope(
				state: \.shareButton,
				action: \.shareButton
			))

			if let ticketButtonStore = store.scope(state: \.ticketButton, action: \.ticketButton) {
				TicketButtonView(store: ticketButtonStore)
			}

			AndroidStudioButtonView(store: store.scope(
				state: \.androidStudioButton,
				action: \.androidStudioButton
			))
			.environmentObject(abbreviationMode)

			TerminalButtonView(store: store.scope(
				state: \.terminalButton,
				action: \.terminalButton
			))
			.environmentObject(abbreviationMode)

			XcodeProjectButtonView(store: store.scope(
				state: \.xcodeButton,
				action: \.xcodeButton
			))
			.environmentObject(abbreviationMode)

			ClaudeCodeButtonView(store: store.scope(
				state: \.claudeCodeButton,
				action: \.claudeCodeButton
			))
			.environmentObject(abbreviationMode)

			Group {
				if store.isWorktree {
					DeleteWorktreeButtonView(store: store.scope(
						state: \.deleteWorktreeButton,
						action: \.deleteWorktreeButton
					))
				}
				else {
					CreateWorktreeButtonView(store: store.scope(
						state: \.createWorktreeButton,
						action: \.createWorktreeButton
					))
				}
			}
			.frame(width: 20, height: 20)
		}
	}

	// MARK: - Computed Properties

	private var backgroundColorForState: Color {
		if let ticketState = store.ticketState {
			switch ticketState {
			case .accepted,
			     .done,
			     .waitingToAcceptation:
				return Color.mint.opacity(0.1)

			case .inProgress:
				return Color.orange.opacity(0.1)

			case .open,
			     .waitingForTesting,
			     .waitingToCodeReview:
				return Color(NSColor.controlBackgroundColor).opacity(0.5)
			}
		}
		return Color(NSColor.controlBackgroundColor).opacity(0.5)
	}

	// MARK: - Helper Methods

	private func copyToClipboard(_ text: String) {
		let pasteboard = NSPasteboard.general
		pasteboard.clearContents()
		pasteboard.setString(text, forType: .string)
	}

	private func openInFinder(_ path: String) {
		NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
	}
}

#Preview {
	RepositoryRowView(
		store: Store(
			initialState: RepositoryRowReducer.State(
				path: "/Users/username/projects/my-project",
				name: "my-project",
				isWorktree: false
			),
			reducer: {
				RepositoryRowReducer()
			}
		)
	)
	.environmentObject(AbbreviationMode())
}
