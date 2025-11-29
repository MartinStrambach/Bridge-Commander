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
				isMergeInProgress: store.isMergeInProgress
			)
			repositoryInfo
			Spacer()
			repositoryActions
		}
		.padding(.horizontal, 16)
		.padding(.vertical, 12)
		.background(Color(NSColor.controlBackgroundColor).opacity(0.5))
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
			if store.isMergeInProgress {
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
				let waiting = androidCR.lowercased() == "passed" || androidCR.lowercased() == "n/a"
				HStack(spacing: 4) {
					Image("android")
						.resizable()
						.renderingMode(.template)
						.scaledToFit()
						.frame(height: 12)
						.foregroundColor(waiting ? .secondary : .orange.opacity(0.75))
					Text(androidCR)
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
				let waiting = iosCR.lowercased() == "passed" || iosCR.lowercased() == "n/a"
				HStack(spacing: 4) {
					Image(systemName: "apple.logo")
						.renderingMode(.template)
						.foregroundColor(waiting ? .secondary : .orange.opacity(0.75))
					Text(iosCR)
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
			// Copy path button
			ActionButton(
				icon: "doc.on.doc",
				tooltip: "Copy path to clipboard",
				action: { copyToClipboard(store.path) }
			)

			// Open in Finder button
			ActionButton(
				icon: "folder",
				tooltip: "Open in Finder",
				action: { openInFinder(store.path) }
			)

			// Open PR button (conditional)
			if let prUrl = store.prUrl {
				Button(action: {
					if let url = URL(string: prUrl) {
						NSWorkspace.shared.open(url)
					}
				}) {
					Image(systemName: "link")
						.foregroundColor(.blue)
				}
				.buttonStyle(.plain)
				.help("Open pull request in Gitlab")
			}

			ShareButtonView(store: store.scope(
				state: \.shareButton,
				action: \.shareButton
			))

			if let ticketButtonStore = store.scope(state: \.ticketButton, action: \.ticketButton) {
				TicketButtonView(store: ticketButtonStore)
					.environmentObject(abbreviationMode)
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

// MARK: - Icon Action Button Component

private struct ActionButton: View {
	let icon: String
	let tooltip: String
	let action: () -> Void

	var body: some View {
		Button(action: action) {
			Image(systemName: icon)
				.foregroundColor(.secondary)
		}
		.buttonStyle(.plain)
		.help(tooltip)
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
