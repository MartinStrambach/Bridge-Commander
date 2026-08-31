import ActionButtons
import AppUI
import ComposableArchitecture
import GitActionsMenu
import GitHosting
import Settings
import StagingFeature
import SwiftUI
import TerminalFeature
import ToolsIntegration
import YouTrackMenu

struct RepositoryRowView: View {
	@Bindable
	var store: StoreOf<RepositoryRowReducer>

	@Environment(\.openSettings)
	private var openSettings

	var terminalSessionStatus: TerminalSessionStatus?

	/// Non-nil when this row is a repo group section header.
	/// Drives the disclosure chevron on the left.
	var isGroupCollapsed: Bool?
	/// Called when the disclosure chevron is tapped. Required when `isGroupCollapsed` is non-nil.
	var onToggleCollapse: (() -> Void)?
	/// Non-nil when this row is a repo group section header.
	/// Renders a remove button in the action bar.
	var onRemove: (() -> Void)?
	/// Total number of worktrees belonging to this repo. Non-nil only for group header rows.
	/// Deliberately the full count, not the search-filtered one — it describes the repo, not the filter.
	var worktreeCount: Int?

	/// Ticket state deliberately doesn't colour the row at all — neither its background nor its
	/// text. Sorting by state groups the rows under state headers, and in the other sort modes a
	/// per-row tint only made the list noisy.
	private var backgroundColor: Color {
		isGroupCollapsed != nil
			? Color.primary.opacity(0.1)
			: Color(NSColor.controlBackgroundColor).opacity(0.5)
	}

	var body: some View {
		HStack(alignment: .center, spacing: 16) {
			if isGroupCollapsed != nil {
				if let collapsed = isGroupCollapsed, let toggle = onToggleCollapse {
					Button(action: toggle) {
						Image(systemName: "chevron.right")
							.font(.caption)
							.foregroundColor(.secondary)
							.rotationEffect(.degrees(collapsed ? 0 : 90))
							.animation(.easeInOut(duration: 0.2), value: collapsed)
							.frame(maxHeight: .infinity)
							.padding(.horizontal, 8)
							.background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
							.contentShape(Rectangle())
					}
					.buttonStyle(.plain)
					.padding(.vertical, 12)
				}
				else {
					Image(systemName: "chevron.right")
						.font(.caption)
						.padding(.horizontal, 8)
						.padding(.vertical, 12)
						.hidden()
				}
			}
			// The double-tap target deliberately covers only the informational part of
			// the row, never `repositoryActions` or the disclosure chevron. A
			// `TapGesture(count: 2)` above a button forces every click on that button
			// to wait out the double-click interval before the gesture system can
			// resolve which one wins, which makes the buttons feel sluggish;
			// `simultaneousGesture` avoids the wait only by firing both.
			HStack(alignment: .center, spacing: 16) {
				TerminalStatusDotView(status: terminalSessionStatus, size: 18)
				RepositoryIcon(
					isWorktree: store.isWorktree,
					isMergeInProgress: store.gitActionsMenu.isMergeInProgress
				)
				repositoryInfo
				Spacer(minLength: 0)
			}
			// Own the vertical padding rather than inheriting it from the outer stack,
			// so the hit region covers the full row height instead of stopping at the
			// content. Every sibling carries the same padding, which keeps the row
			// height identical to putting it on the outer stack. Deliberately no
			// `frame(maxHeight: .infinity)`: that would make this container flexible,
			// so the stack would size itself from the shorter action buttons instead.
			.padding(.vertical, 12)
			.contentShape(Rectangle())
			.gesture(
				TapGesture(count: 2)
					.onEnded {
						store.send(.openTerminalForRepo)
					}
			)
			repositoryActions
				.padding(.vertical, 12)
		}
		.padding(.horizontal, 16)
		.background(backgroundColor)
		.task {
			store.send(.onAppear)
		}
		.sheet(item: $store.scope(\.$repositoryDetail, action: \.repositoryDetail)) { detailStore in
			RepositoryDetailView(store: detailStore)
				.frame(
					minWidth: 1200,
					idealWidth: 1500,
					maxWidth: .infinity,
					minHeight: 700,
					idealHeight: 800,
					maxHeight: .infinity
				)
		}
	}

	// MARK: - Repository Info

	private var repositoryInfo: some View {
		VStack(alignment: .leading, spacing: 4) {
			HStack(spacing: 12) {
				VStack(alignment: .leading, spacing: 2) {
					HStack(spacing: 8) {
						Text(isGroupCollapsed != nil ? store.name : store.formattedBranchName)
							.font(.headline)
							.lineLimit(1)
						if let worktreeCount, worktreeCount > 0 {
							worktreeCountBadge(worktreeCount)
						}
						changesIndicator
					}

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

							if store.gitActionsMenu.isMergeInProgress {
								HStack(spacing: 4) {
									Image(systemName: "arrow.triangle.merge")
										.foregroundColor(.red)
									Text("Merge")
										.lineLimit(1)
										.font(.caption)
								}
							}

							if !store.hasRemoteBranch {
								HStack(spacing: 4) {
									Image(systemName: "icloud.slash.fill")
										.foregroundColor(.orange)
									Text("No remote")
										.lineLimit(1)
										.font(.caption)
										.foregroundColor(.orange)
								}
							}
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

	// MARK: - Worktree Count Badge

	/// Matches the worktree row icon (`tree.fill`, blue) so the badge reads as "this repo has N worktrees".
	private func worktreeCountBadge(_ count: Int) -> some View {
		HStack(spacing: 3) {
			Image(systemName: "tree.fill")
				.font(.caption2)
			Text("\(count)")
				.font(.caption)
				.lineLimit(1)
		}
		.foregroundColor(.blue)
		.padding(.horizontal, 6)
		.padding(.vertical, 2)
		.background(Color.blue.opacity(0.15), in: Capsule())
		.help(count == 1 ? "1 worktree" : "\(count) worktrees")
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
						.lineLimit(1)
						.font(.caption)
				}
			}

			// Unstaged changes
			if store.unstagedChangesCount > 0 {
				HStack(spacing: 4) {
					Image(systemName: "pencil.circle.fill")
						.foregroundColor(.orange)
					Text("\(store.unstagedChangesCount)")
						.lineLimit(1)
						.font(.caption)
				}
			}

			// Unpushed commits
			if store.unpushedCommitCount > 0 {
				HStack(spacing: 4) {
					Image(systemName: "arrow.up.circle.fill")
						.foregroundColor(.red)
					Text("\(store.unpushedCommitCount)")
						.lineLimit(1)
						.font(.caption)
				}
			}

			// Commits behind (need to pull)
			if store.commitsBehindCount > 0 {
				HStack(spacing: 4) {
					Image(systemName: "arrow.down.circle.fill")
						.foregroundColor(.blue)
					Text("\(store.commitsBehindCount)")
						.lineLimit(1)
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
				let activeColor: Color = androidCR == .inProgress ? .green : .orange
				HStack(spacing: 4) {
					Image("android")
						.resizable()
						.renderingMode(.template)
						.scaledToFit()
						.frame(height: 12)
						.foregroundColor(waiting ? .secondary : activeColor.opacity(0.75))
					Text(androidCR.rawValue)
						.font(.caption)
						.foregroundColor(waiting ? .secondary : activeColor.opacity(0.75))
						.lineLimit(1)
					if let reviewerName = store.androidReviewerName {
						Text("(\(reviewerName))")
							.font(.caption2)
							.foregroundColor(waiting ? .secondary : activeColor)
							.lineLimit(1)
					}
				}
				.padding(6)
				.cornerRadius(4)
			}

			if let iosCR = store.iosCR {
				let waiting = iosCR == .passed || iosCR == .notApplicable || store.ticketState != .waitingToCodeReview
				let activeColor: Color = iosCR == .inProgress ? .green : .orange
				HStack(spacing: 4) {
					Image(systemName: "apple.logo")
						.renderingMode(.template)
						.foregroundColor(waiting ? .secondary : activeColor.opacity(0.75))
					Text(iosCR.rawValue)
						.font(.caption)
						.foregroundColor(waiting ? .secondary : activeColor.opacity(0.75))
						.lineLimit(1)
					if let reviewerName = store.iosReviewerName {
						Text("(\(reviewerName))")
							.font(.caption2)
							.foregroundColor(waiting ? .secondary : activeColor)
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
				\.gitActionsMenu,
				action: \.gitActionsMenu
			))

			if store.supportsIOS, store.supportsTuist {
				TuistButtonView(store: store.scope(
					\.tuistButton,
					action: \.tuistButton
				))
			}

			// Grouped with the other dropdowns rather than next to the ticket icon, so the
			// text-label menus stay together on the left of the icon buttons.
			if let youtrackButtonStore = store.scope(\.youtrackButton, action: \.youtrackButton) {
				YouTrackButtonView(store: youtrackButtonStore)
			}

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

			// PR/MR fetch failure (conditional) — sits where the PR badge would, so a
			// missing or stale badge and its cause are read in the same place.
			if let prFetchError = store.prFetchError {
				Image(systemName: "exclamationmark.triangle.fill")
					.resizable()
					.scaledToFit()
					.padding(4)
					.frame(width: 25, height: 25)
					.foregroundColor(.orange)
					.help(prFetchError)
			}

			// Open PR button (conditional), with unresolved discussions stacked below
			if let prUrl = store.prUrl, let url = URL(string: prUrl) {
				VStack(alignment: .center, spacing: 2) {
					PullRequestButton(
						url: url,
						provider: store.prProvider,
						state: store.prState
					)

					// Unresolved review discussions (conditional)
					if let count = store.prUnresolvedDiscussions, count > 0 {
						UnresolvedDiscussionsBadge(
							count: count,
							url: url,
							provider: store.prProvider
						)
					}
				}
				// The action bar can be narrower than its ideal width (narrow sidebar
				// pane); without this the HStack compresses the badge, deleting the
				// count text and leaving an off-center bubble icon.
				.fixedSize(horizontal: true, vertical: false)
			}

			// GitLab pipeline status (conditional)
			if let pipelineUrl = store.pipelineUrl,
			   let url = URL(string: pipelineUrl),
			   let pipelineState = store.pipelineState {
				PipelineStatusButton(url: url, state: pipelineState)
			}

			ShareButtonView(store: store.scope(
				\.shareButton,
				action: \.shareButton
			))

			if let ticketButtonStore = store.scope(\.ticketButton, action: \.ticketButton) {
				TicketButtonView(store: ticketButtonStore)
			}
			else if store.showsMissingYouTrackURLWarning {
				ActionButton(
					icon: .systemImage("exclamationmark.triangle.fill"),
					tooltip: "Ticket \(store.ticketId ?? "") detected, but this repository has no YouTrack URL. "
						+ "Set it in Settings to enable ticket integration.",
					color: .orange,
					action: { openSettings() }
				)
			}

			if let webButtonStore = store.scope(\.webButton, action: \.webButton) {
				WebButtonView(store: webButtonStore)
			}

			TerminalButtonView(store: store.scope(
				\.terminalButton,
				action: \.terminalButton
			))

			if store.supportsAndroid {
				AndroidStudioButtonView(store: store.scope(
					\.androidStudioButton,
					action: \.androidStudioButton
				))
			}

			if store.supportsIOS {
				XcodeProjectButtonView(store: store.scope(
					\.xcodeButton,
					action: \.xcodeButton
				))
			}

			ClaudeCodeButtonView(store: store.scope(
				\.claudeCodeButton,
				action: \.claudeCodeButton
			))

			Group {
				if store.isWorktree {
					DeleteWorktreeButtonView(store: store.scope(
						\.deleteWorktreeButton,
						action: \.deleteWorktreeButton
					))
				}
				else {
					CreateWorktreeButtonView(store: store.scope(
						\.createWorktreeButton,
						action: \.createWorktreeButton
					))
				}
			}
			.frame(width: 20, height: 20)
			if let remove = onRemove {
				ActionButton(
					icon: .systemImage("xmark.circle"),
					tooltip: "Remove from list",
					color: .red,
					action: remove
				)
			}
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

#Preview {
	RepositoryRowView(
		store: Store(
			initialState: RepositoryRowReducer.State(
				path: "/Users/username/projects/my-project",
				name: "my-project",
				branchName: "branch",
				isWorktree: false
			),
			reducer: {
				RepositoryRowReducer()
			}
		)
	)
}
