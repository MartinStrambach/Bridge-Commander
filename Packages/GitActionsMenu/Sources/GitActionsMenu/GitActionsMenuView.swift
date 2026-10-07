import AppUI
import ComposableArchitecture
import GitCore
import SwiftUI

// MARK: - Git Actions Menu View

public struct GitActionsMenuView: View {
	@Bindable
	var store: StoreOf<GitActionsMenuReducer>

	/// Read here and applied to the menu's label as a plain font: a `.borderlessButton` menu's
	/// label is flattened by AppKit, which drops `scaledFont`'s environment lookup and keeps only
	/// a font set directly on the `Text`.
	@Environment(\.uiFontScale)
	private var uiFontScale

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
				Menu {
					GitActionsMenuItems(store: store)
				} label: {
					Text("Git Actions")
						.font(.system(size: 12 * uiFontScale))
				}
				.menuStyle(.borderlessButton)
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

/// The Git Actions menu as a submenu of another menu (the repository row's "⋯" menu). While an
/// operation runs it is a disabled entry naming it instead.
///
/// A menu entry cannot present anything, so whoever shows this must also apply
/// `gitActionsMenuPresentations(store:)` to a view outside the menu.
public struct GitActionsSubmenu: View {
	let store: StoreOf<GitActionsMenuReducer>

	public init(store: StoreOf<GitActionsMenuReducer>) {
		self.store = store
	}

	public var body: some View {
		if let operation = store.runningOperation {
			Button {} label: {
				Label(operation.text, systemImage: "arrow.triangle.branch")
			}
			.disabled(true)
		}
		else {
			Menu {
				GitActionsMenuItems(store: store)
			} label: {
				Label("Git Actions", systemImage: "arrow.triangle.branch")
			}
		}
	}
}

/// The menu's entries, shared by `GitActionsMenuView` and `GitActionsSubmenu`.
struct GitActionsMenuItems: View {
	let store: StoreOf<GitActionsMenuReducer>

	var body: some View {
		Group {
			if store.isMergeInProgress {
				AbortMergeButtonView(store: store.scope(\.abortMergeButton, action: \.abortMergeButton))
			}

			if store.hasRemoteBranch {
				FetchButtonView(store: store.scope(\.fetchButton, action: \.fetchButton))
				PullButtonView(store: store.scope(\.pullButton, action: \.pullButton))
			}

			if store.unpushedCommitsCount > 0 || !store.hasRemoteBranch {
				PushButtonView(store: store.scope(\.pushButton, action: \.pushButton))
			}

			if !store.isMergeInProgress {
				StashButtonView(store: store.scope(\.stashButton, action: \.stashButton))
				DiscardButtonView(store: store.scope(\.discardButton, action: \.discardButton))
			}

			if !DefaultBranchResolver.isDefaultBranch(store.currentBranch, configured: store.defaultBranch),
			   !store.isMergeInProgress
			{
				MergeMasterButtonView(store: store.scope(
					\.mergeMasterButton,
					action: \.mergeMasterButton
				))
				CheckoutDefaultBranchButtonView(store: store.scope(
					\.checkoutDefaultBranchButton,
					action: \.checkoutDefaultBranchButton
				))
			}
		}
		// macOS 27 no longer draws a menu item's icon for a bare `Label`; ask for it explicitly.
		.labelStyle(.titleAndIcon)
	}
}

public extension View {
	/// The Git Actions menu's alert and confirmation dialogs. Applied by `GitActionsMenuView`
	/// itself; a `GitActionsSubmenu` needs it on a view outside the menu it sits in, because
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
