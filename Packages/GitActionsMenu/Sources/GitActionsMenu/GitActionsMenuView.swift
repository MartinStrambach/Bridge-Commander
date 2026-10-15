import AppUI
import ComposableArchitecture
import GitCore
import SwiftUI

// MARK: - Git Actions Menu View

public struct GitActionsMenuView: View {
	@Bindable
	var store: StoreOf<GitActionsMenuReducer>

	public var body: some View {
		Group {
			if let operation = store.runningOperation {
				GitOperationProgressView(
					text: operation.text,
					color: operation.color,
					helpText: operation.helpText
				)
			}
			else {
				PopUpMenuButton("Git Actions") {
					store.menuEntries
				}
				.help("Quick Git Actions")
			}
		}
		.fixedSize()
		.gitActionsMenuPresentations(store: store)
	}

	public init(store: StoreOf<GitActionsMenuReducer>) {
		self.store = store
	}
}

public extension Store where State == GitActionsMenuReducer.State, Action == GitActionsMenuReducer.Action {
	/// The Git Actions menu as an entry of another menu (the repository row's "⋯" menu): a
	/// submenu, or while an operation runs a disabled entry naming it.
	///
	/// A menu entry cannot present anything, so whoever shows this must also apply
	/// `gitActionsMenuPresentations(store:)` to a view outside the menu.
	var submenuEntry: PopUpMenuEntry {
		if let operation = self.runningOperation {
			.action(PopUpMenuAction(operation.text, systemImage: "arrow.triangle.branch", isEnabled: false) {})
		}
		else {
			.submenu("Git Actions", systemImage: "arrow.triangle.branch") {
				self.menuEntries
			}
		}
	}
}

/// The menu's entries, shared by `GitActionsMenuView` and `submenuEntry`.
extension Store where State == GitActionsMenuReducer.State, Action == GitActionsMenuReducer.Action {
	@PopUpMenuBuilder
	var menuEntries: [PopUpMenuEntry] {
		if self.isMergeInProgress {
			PopUpMenuAction("Abort Merge", systemImage: "xmark.circle", isDestructive: true) {
				self.send(.abortMergeButton(.abortMergeTapped))
			}
		}

		if self.hasRemoteBranch {
			PopUpMenuAction("Fetch", systemImage: "arrow.down.circle.dotted") {
				self.send(.fetchButton(.fetchTapped))
			}
			PopUpMenuAction("Pull", systemImage: "arrow.down.circle") {
				self.send(.pullButton(.pullTapped))
			}
		}

		if self.unpushedCommitsCount > 0 || !self.hasRemoteBranch {
			PopUpMenuAction("Push", systemImage: "arrow.up.circle") {
				self.send(.pushButton(.pushTapped))
			}
		}

		if !self.isMergeInProgress {
			stashEntries
			discardEntries
		}

		if !DefaultBranchResolver.isDefaultBranch(self.currentBranch, configured: self.defaultBranch), !self.isMergeInProgress {
			PopUpMenuAction("Merge \(Self.branchTitle(self.mergeMasterButton.defaultBranch))", systemImage: "arrow.triangle.merge") {
				self.send(.mergeMasterButton(.mergeMasterTapped))
			}
			PopUpMenuAction(
				"Checkout \(Self.branchTitle(self.checkoutDefaultBranchButton.defaultBranch))",
				systemImage: "arrow.triangle.branch"
			) {
				self.send(.checkoutDefaultBranchButton(.checkoutTapped))
			}
			PopUpMenuAction(
				"Checkout & Pull \(Self.branchTitle(self.checkoutDefaultBranchButton.defaultBranch))",
				systemImage: "arrow.down.to.line.circle"
			) {
				self.send(.checkoutDefaultBranchButton(.checkoutAndPullTapped))
			}
		}
	}

	/// Restoring the work and keeping the entry are separate decisions, so each combination gets
	/// its own item: apply restores and keeps, pop restores and drops, clear only drops. Clear
	/// confirms first — see StashButtonReducer.
	@PopUpMenuBuilder
	private var stashEntries: [PopUpMenuEntry] {
		let isProcessing = self.stashButton.isProcessing
		if self.stashButton.hasChanges {
			PopUpMenuAction("Stash", systemImage: "tray.and.arrow.down", isEnabled: !isProcessing) {
				self.send(.stashButton(.stashTapped))
			}
		}

		if self.stashButton.hasStash {
			PopUpMenuAction("Apply Stash", systemImage: "tray.and.arrow.up", isEnabled: !isProcessing) {
				self.send(.stashButton(.stashApplyTapped))
			}
			PopUpMenuAction("Pop Stash", systemImage: "tray.and.arrow.up.fill", isEnabled: !isProcessing) {
				self.send(.stashButton(.stashPopTapped))
			}
			PopUpMenuAction("Clear Stash", systemImage: "trash", isDestructive: true, isEnabled: !isProcessing) {
				self.send(.stashButton(.stashClearTapped))
			}
		}
	}

	@PopUpMenuBuilder
	private var discardEntries: [PopUpMenuEntry] {
		let isProcessing = self.discardButton.isProcessing
		if self.discardButton.hasTrackedChanges {
			PopUpMenuAction(
				"Discard Tracked Changes",
				systemImage: "arrow.uturn.backward",
				isDestructive: true,
				isEnabled: !isProcessing
			) {
				self.send(.discardButton(.discardTrackedTapped))
			}
		}

		if self.discardButton.hasUntrackedFiles {
			PopUpMenuAction("Discard All Changes", systemImage: "trash", isDestructive: true, isEnabled: !isProcessing) {
				self.send(.discardButton(.discardAllTapped))
			}
		}
	}

	private static func branchTitle(_ defaultBranch: String) -> String {
		defaultBranch.isEmpty ? "default branch" : defaultBranch
	}
}

public extension View {
	/// The Git Actions menu's alert and confirmation dialogs. Applied by `GitActionsMenuView`
	/// itself; a `submenuEntry` needs it on a view outside the menu it sits in, because
	/// dialogs attached inside a macOS `Menu` do not present reliably.
	func gitActionsMenuPresentations(store: StoreOf<GitActionsMenuReducer>) -> some View {
		modifier(GitActionsMenuPresentations(store: store))
	}
}

private struct GitActionsMenuPresentations: ViewModifier {
	@Bindable
	var store: StoreOf<GitActionsMenuReducer>

	func body(content: Content) -> some View {
		content
			.sheet(item: $store.scope(\.$alert, action: \.alert)) { alertStore in
				ScrollableAlertView(store: alertStore)
			}
			.confirmationDialog(
				$store.scope(\.discardButton.$confirmationDialog, action: \.discardButton.confirmationDialog)
			)
			// Presented here rather than on the menu item, for the same reason as the discard
			// dialog above: dialogs attached inside a macOS `Menu` do not present reliably.
			.confirmationDialog(
				$store.scope(\.stashButton.$confirmationDialog, action: \.stashButton.confirmationDialog)
			)
	}
}

/// The operation in flight, which replaces the menu until it finishes.
struct GitRunningOperation {
	let text: String
	let color: Color
	let helpText: String
}

extension GitActionsMenuReducer.State {
	var runningOperation: GitRunningOperation? {
		let defaultBranchName = defaultBranch.isEmpty ? "default" : defaultBranch
		if fetchButton.isFetching {
			return GitRunningOperation(text: "Fetching...", color: .cyan, helpText: "Fetching updates from remote...")
		}
		if pullButton.isPulling {
			return GitRunningOperation(text: "Pulling...", color: .blue, helpText: "Pulling changes from remote...")
		}
		if pushButton.isPushing {
			return GitRunningOperation(text: "Pushing...", color: .green, helpText: "Pushing commits to remote...")
		}
		if mergeMasterButton.isMergingMaster {
			return GitRunningOperation(
				text: "Merging...",
				color: .orange,
				helpText: "Merging \(defaultBranchName) branch..."
			)
		}
		if checkoutDefaultBranchButton.isPullingAfterCheckout {
			return GitRunningOperation(
				text: "Checking out...",
				color: .teal,
				helpText: "Checking out and pulling \(defaultBranchName) branch..."
			)
		}
		if checkoutDefaultBranchButton.isCheckingOut {
			return GitRunningOperation(
				text: "Checking out...",
				color: .teal,
				helpText: "Checking out \(defaultBranchName) branch..."
			)
		}
		if abortMergeButton.isAbortingMerge {
			return GitRunningOperation(text: "Aborting...", color: .red, helpText: "Aborting merge...")
		}
		if let operation = stashButton.operation {
			return GitRunningOperation(
				text: operation.progressText,
				color: .purple,
				helpText: operation.progressHelpText
			)
		}
		if discardButton.isProcessing {
			return GitRunningOperation(text: "Discarding...", color: .red, helpText: "Discarding local changes...")
		}
		return nil
	}
}

#Preview("Idle") {
	GitActionsMenuView(
		store: Store(
			initialState: GitActionsMenuReducer.State(
				repositoryPath: "/Users/test/projects/my-project",
				currentBranch: "feature/test"
			),
			reducer: {
				GitActionsMenuReducer()
			}
		)
	)
	.padding()
}

#Preview("On Master") {
	GitActionsMenuView(
		store: Store(
			initialState: GitActionsMenuReducer.State(
				repositoryPath: "/Users/test/projects/my-project",
				currentBranch: "master"
			),
			reducer: {
				GitActionsMenuReducer()
			}
		)
	)
	.padding()
}
