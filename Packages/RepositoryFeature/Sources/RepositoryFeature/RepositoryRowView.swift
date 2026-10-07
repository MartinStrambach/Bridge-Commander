import ActionButtons
import AppUI
import ComposableArchitecture
import GitActionsMenu
import GitGraphFeature
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
	var openSettings

	@Environment(\.uiFontScale)
	private var uiFontScale

	@SharedReader(.repositoryRowLayout)
	private var rowLayout = RepositoryRowLayout.default

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
							.scaledFont(.caption)
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
						.scaledFont(.caption)
						.padding(.horizontal, 8)
						.padding(.vertical, 12)
						.hidden()
				}
			}
			TerminalStatusDotView(status: terminalSessionStatus, size: 18)
				.padding(.vertical, 12)
			// Outside the double-tap region below, like every other button in the row: a
			// `TapGesture(count: 2)` above a button forces every click on that button to
			// wait out the double-click interval before the gesture system can resolve
			// which one wins, which makes the button feel sluggish.
			graphButton
				.padding(.vertical, 12)
			// The double-tap target deliberately covers only the informational part of
			// the row, never `repositoryActions`, the icon or the disclosure chevron;
			// `simultaneousGesture` avoids the wait described above only by firing both.
			HStack(alignment: .center, spacing: 16) {
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
			// The lowest priority, so the stack sets this minimum aside and lets the actions
			// take what is left: `RowActionsLayout` wraps onto a second line when one line no
			// longer fits, instead of the title shrinking to an ellipsis.
			.frame(minWidth: 260 * uiFontScale, alignment: .leading)
			.layoutPriority(-1)
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
		.sheet(item: $store.scope(\.$gitGraph, action: \.gitGraph)) { graphStore in
			GitGraphView(store: graphStore)
				// Roomier than the graph alone needs: the selected commit's diff opens in a
				// bottom pane, and both panes have to stay usable at the ideal size.
				.frame(
					minWidth: 1000,
					idealWidth: 1400,
					maxWidth: .infinity,
					minHeight: 600,
					idealHeight: 900,
					maxHeight: .infinity
				)
				.windowResizable()
		}
	}

	// MARK: - Graph Button

	/// The repository type icon doubles as the commit graph's entry point.
	private var graphButton: some View {
		Button {
			store.send(.repositoryIconTapped)
		} label: {
			RepositoryIcon(
				isWorktree: store.isWorktree,
				isMergeInProgress: store.gitActionsMenu.isMergeInProgress
			)
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.help("Show commit graph")
	}

	// MARK: - Repository Info

	private var repositoryInfo: some View {
		VStack(alignment: .leading, spacing: 4) {
			HStack(spacing: 12) {
				VStack(alignment: .leading, spacing: 2) {
					HStack(spacing: 8) {
						// Two lines rather than one: a ticket summary is often longer than the
						// space a narrow window leaves, and its end is what tells tickets apart.
						Text(isGroupCollapsed != nil ? store.name : store.formattedBranchName)
							.scaledFont(.headline)
							.lineLimit(2)
						if let worktreeCount, worktreeCount > 0 {
							worktreeCountBadge(worktreeCount)
						}
						changesIndicator
					}

					// Branch with icon
					if let branchName = store.branchName {
						HStack(spacing: 4) {
							Image(systemName: "arrow.trianglehead.branch")
								.scaledFont(.caption)
								.foregroundColor(.secondary)
							Text(branchName)
								.scaledFont(.caption)
								.foregroundColor(.secondary)
								.lineLimit(1)
								.truncationMode(.middle)

							if store.gitActionsMenu.isMergeInProgress {
								HStack(spacing: 4) {
									Image(systemName: "arrow.triangle.merge")
										.foregroundColor(.red)
									Text("Merge")
										.lineLimit(1)
										.scaledFont(.caption)
								}
							}

							if !store.hasRemoteBranch {
								HStack(spacing: 4) {
									Image(systemName: "icloud.slash.fill")
										.foregroundColor(.orange)
									Text("No remote")
										.lineLimit(1)
										.scaledFont(.caption)
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
				.scaledFont(.caption2)
			Text("\(count)")
				.scaledFont(.caption)
				.lineLimit(1)
		}
		.foregroundColor(.blue)
		.padding(.horizontal, 6)
		.padding(.vertical, 2)
		.background(Color.blue.opacity(0.15), in: Capsule())
		.help(count == 1 ? "1 worktree" : "\(count) worktrees")
	}

	// MARK: - Ticket Badge

	/// The ticket ID, clickable whenever the row managed to resolve a YouTrack URL for it.
	///
	/// Goes through the scoped ticket store rather than opening `ticketURL` here, so the badge and
	/// the ticket button in the action bar share one code path. Without a configured YouTrack base
	/// URL there is no store and the badge stays plain text — the action bar's orange warning
	/// button is what explains why in that case.
	@ViewBuilder
	private func ticketBadge(_ ticketId: String) -> some View {
		if let ticketStore = store.scope(\.ticketButton, action: \.ticketButton) {
			Button {
				ticketStore.send(.openTicketButtonTapped)
			} label: {
				ticketBadgeLabel(ticketId)
			}
			.buttonStyle(.plain)
			.pointerStyle(.link)
			.help("Open YouTrack ticket \(ticketId)")
		}
		else {
			ticketBadgeLabel(ticketId)
		}
	}

	private func ticketBadgeLabel(_ ticketId: String) -> some View {
		Text(ticketId)
			.scaledFont(.caption)
			.padding(6)
			.background(Color.blue.opacity(0.2))
			.cornerRadius(4)
			.lineLimit(1)
			// Never truncated: a bare "…" badge says nothing, and the code review states beside
			// it can give up their width instead.
			.fixedSize()
			.contentShape(Rectangle())
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
						.scaledFont(.caption)
				}
			}

			// Unstaged changes
			if store.unstagedChangesCount > 0 {
				HStack(spacing: 4) {
					Image(systemName: "pencil.circle.fill")
						.foregroundColor(.orange)
					Text("\(store.unstagedChangesCount)")
						.lineLimit(1)
						.scaledFont(.caption)
				}
			}

			// Unpushed commits
			if store.unpushedCommitCount > 0 {
				HStack(spacing: 4) {
					Image(systemName: "arrow.up.circle.fill")
						.foregroundColor(.red)
					Text("\(store.unpushedCommitCount)")
						.lineLimit(1)
						.scaledFont(.caption)
				}
			}

			// Commits behind (need to pull)
			if store.commitsBehindCount > 0 {
				HStack(spacing: 4) {
					Image(systemName: "arrow.down.circle.fill")
						.foregroundColor(.blue)
					Text("\(store.commitsBehindCount)")
						.lineLimit(1)
						.scaledFont(.caption)
				}
			}
		}
	}

	// MARK: - Code Review Section

	private var codeReviewSection: some View {
		HStack(spacing: 8) {
			if let ticketId = store.ticketId {
				ticketBadge(ticketId)
			}

			if let androidCR = store.androidCR {
				let color = codeReviewColor(androidCR)
				HStack(spacing: 4) {
					Image("android")
						.resizable()
						.renderingMode(.template)
						.scaledToFit()
						.frame(height: 12)
						.foregroundColor(color.opacity(0.75))
					Text(androidCR.rawValue)
						.scaledFont(.caption)
						.foregroundColor(color.opacity(0.75))
						.lineLimit(1)
					if let reviewerName = store.androidReviewerName {
						Text("(\(reviewerName))")
							.scaledFont(.caption2)
							.foregroundColor(color)
							.lineLimit(1)
					}
				}
				.padding(6)
				.cornerRadius(4)
			}

			if let iosCR = store.iosCR {
				let color = codeReviewColor(iosCR)
				HStack(spacing: 4) {
					Image(systemName: "apple.logo")
						.renderingMode(.template)
						.foregroundColor(color.opacity(0.75))
					Text(iosCR.rawValue)
						.scaledFont(.caption)
						.foregroundColor(color.opacity(0.75))
						.lineLimit(1)
					if let reviewerName = store.iosReviewerName {
						Text("(\(reviewerName))")
							.scaledFont(.caption2)
							.foregroundColor(color)
							.lineLimit(1)
					}
				}
				.padding(6)
				.cornerRadius(4)
			}
		}
	}

	/// The same colors YouTrack gives these values, so a state reads the same in both places.
	private func codeReviewColor(_ state: CodeReviewState) -> Color {
		switch state {
		case .waiting: .orange
		case .inProgress: .blue
		case .passed: .green
		case .notApplicable: .secondary
		}
	}

	// MARK: - Repository Actions

	private var repositoryActions: some View {
		HStack(spacing: 8) {
			RowActionsLayout {
				ForEach(rowLayout.rowSlots) { slot in
					switch slot {
					case let .item(item):
						smallAction(item)
					case let .menuStack(menus):
						VStack(alignment: .leading, spacing: 4) {
							ForEach(menus) { menu in
								smallAction(menu)
							}
						}
					}
				}
				if rowLayout.showsMoreMenu {
					moreActionsMenu(items: rowLayout.moreMenuItems)
				}
			}

			ForEach(rowLayout.items(in: .toolButtons, placedIn: .row)) { item in
				toolButton(item)
			}
			.environment(\.toolButtonSize, rowLayout.toolButtonSize)

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
		// The alerts and dialogs of the items moved into the "⋯" menu, which cannot present them
		// from inside it. Only for those items: one in the row presents its own, and a second
		// presenter of the same state would fight it.
		.background {
			ForEach(rowLayout.moreMenuItems) { item in
				moreMenuPresenter(item)
			}
		}
	}

	/// One of the menus and icon buttons left of the tool buttons. Which ones show, and in what
	/// order, is the user's `RepositoryRowLayout`; `RowActionsLayout` wraps them onto a second
	/// line in a narrow row. An item that does not apply to this repository draws nothing.
	@ViewBuilder
	private func smallAction(_ item: RepositoryRowItem) -> some View {
		switch item {
		case .gitActions:
			GitActionsMenuView(store: store.scope(
				\.gitActionsMenu,
				action: \.gitActionsMenu
			))

		case .tuist:
			if store.supportsIOS, store.supportsTuist {
				TuistButtonView(store: store.scope(
					\.tuistButton,
					action: \.tuistButton
				))
			}

		case .youTrackMenu:
			if let youtrackButtonStore = store.scope(\.youtrackButton, action: \.youtrackButton) {
				YouTrackButtonView(store: youtrackButtonStore)
			}

		case .pullRequest:
			// PR/MR fetch failure — sits where the PR badge would, so a missing or stale badge
			// and its cause are read in the same place.
			if let prFetchError = store.prFetchError {
				Image(systemName: "exclamationmark.triangle.fill")
					.resizable()
					.scaledToFit()
					.padding(4)
					.frame(width: 25, height: 25)
					.foregroundColor(.orange)
					.help(prFetchError)
			}

			// Open PR button, with unresolved discussions stacked below
			if let prUrl = store.prUrl, let url = URL(string: prUrl) {
				VStack(alignment: .center, spacing: 2) {
					PullRequestButton(
						url: url,
						provider: store.prProvider,
						state: store.prState
					)

					if let count = store.prUnresolvedDiscussions, count > 0 {
						UnresolvedDiscussionsBadge(
							count: count,
							url: url,
							provider: store.prProvider
						)
					}
				}
				// Keeps the badge's count text from being compressed away.
				.fixedSize(horizontal: true, vertical: false)
			}

		case .pipeline:
			if let pipelineUrl = store.pipelineUrl,
			   let url = URL(string: pipelineUrl),
			   let pipelineState = store.pipelineState {
				PipelineStatusButton(url: url, state: pipelineState, hasConflicts: store.prHasConflicts)
			}

		case .approval:
			// Review sign-off, or a draft marker
			if let slot = store.approvalSlot,
			   let prUrl = store.prUrl,
			   let url = URL(string: prUrl) {
				ApprovalSlotView(slot: slot, url: url, provider: store.prProvider)
			}

		case .ticket:
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

		case .web:
			if let webButtonStore = store.scope(\.webButton, action: \.webButton) {
				WebButtonView(store: webButtonStore)
			}

		case .terminal:
			TerminalButtonView(store: store.scope(
				\.terminalButton,
				action: \.terminalButton
			))

		case .copyPath:
			ActionButton(
				icon: .systemImage("doc.on.doc"),
				tooltip: "Copy path to clipboard",
				action: { copyToClipboard(store.path) }
			)

		case .showInFinder:
			ActionButton(
				icon: .systemImage("folder"),
				tooltip: "Open in Finder",
				action: { openInFinder(store.path) }
			)

		case .share:
			ShareButtonView(store: store.scope(
				\.shareButton,
				action: \.shareButton
			))

		case .androidStudio, .xcode, .claudeCode:
			EmptyView()
		}
	}

	/// One of the large buttons at the end of the row, drawn at the size `RepositoryRowLayout`
	/// picks (applied by the caller through the `toolButtonSize` environment value).
	@ViewBuilder
	private func toolButton(_ item: RepositoryRowItem) -> some View {
		switch item {
		case .androidStudio:
			if store.supportsAndroid {
				AndroidStudioButtonView(store: store.scope(
					\.androidStudioButton,
					action: \.androidStudioButton
				))
			}

		case .xcode:
			if store.supportsIOS {
				XcodeProjectButtonView(store: store.scope(
					\.xcodeButton,
					action: \.xcodeButton
				))
			}

		case .claudeCode:
			ClaudeCodeButtonView(store: store.scope(
				\.claudeCodeButton,
				action: \.claudeCodeButton
			))

		default:
			EmptyView()
		}
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
