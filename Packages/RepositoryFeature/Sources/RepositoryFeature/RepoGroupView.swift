import ComposableArchitecture
import SwiftUI
import Settings
import TerminalFeature
import UniformTypeIdentifiers

struct RepoGroupView: View {
	@Bindable var store: StoreOf<RepoGroupReducer>

	/// Terminal session status keyed by repository path. O(1) lookup per row, built once by the parent.
	let statusByPath: [String: TerminalSessionStatus]

	/// Active branch-name query. Empty shows every row.
	var searchText: String = ""

	/// Repository paths with a live terminal session, or `nil` when the active-terminal filter is
	/// off. Built once by the parent.
	var livePaths: Set<String>?

	/// The list's active sort. Decides what the worktree rows are split under: state headers, ticket
	/// headers, or nothing.
	var sortMode: SortMode = .state

	/// Another repository was dropped on this group's header — it takes this group's place.
	/// The dragged repository's path is passed through; `nil` makes the header undraggable.
	var onRepositoryDropped: ((String) -> Void)?

	/// Whether a dragged repository is currently over this group's header, which draws the
	/// insertion line. Local to the view: nothing outside it reads a hover.
	@State
	private var isDropTargeted = false

	var body: some View {
		let isExpanded = Binding(
			get: { !store.isCollapsed },
			set: { newValue in
				if newValue != !store.isCollapsed {
					store.send(.toggleCollapse)
				}
			}
		)
		// Resolved here rather than by the parent so a keystroke invalidates each group's own body
		// instead of the whole list's.
		let visibility = store.state.rowVisibility(query: searchText, livePaths: livePaths)
		let hasVisibleWorktrees = store.worktrees.contains { visibility.includesWorktree(id: $0.id) }
		// Resolved alongside `visibility` for the same reason: only this group's rows are read, so a
		// header appearing or moving invalidates one group's body rather than the whole list's.
		let sectionHeaders = store.state.sectionHeaders(sortMode: sortMode, visibility: visibility)

		if !visibility.isHidden {
			Section(isExpanded: isExpanded) {
				ForEach(store.scope(\.worktrees, action: \.worktrees)) { rowStore in
					if visibility.includesWorktree(id: rowStore.id) {
						if let sectionHeader = sectionHeaders[rowStore.id] {
							RowSectionHeaderView(header: sectionHeader)
								.padding(.leading, 20)
								.listRowInsets(EdgeInsets())
								.listRowSeparator(.hidden)
						}
						RepositoryRowView(
							store: rowStore,
							terminalSessionStatus: statusByPath[rowStore.path]
						)
						.padding(.leading, 20)
						.listRowInsets(EdgeInsets())
					}
				}
			} header: {
				RepositoryRowView(
					store: store.scope(\.header, action: \.header),
					terminalSessionStatus: statusByPath[store.header.path],
					isGroupCollapsed: store.isCollapsed,
					onToggleCollapse: hasVisibleWorktrees
						? { isExpanded.wrappedValue = !isExpanded.wrappedValue } : nil,
					onRemove: { store.send(.remove) },
					worktreeCount: store.worktrees.count
				)
				.reorderable(
					path: store.id,
					isEnabled: onRepositoryDropped != nil,
					isTargeted: $isDropTargeted,
					onDrop: { onRepositoryDropped?($0) }
				)
			}
			.listSectionSeparator(.hidden)
		}
	}
}

private extension View {
	/// Makes a repository header row both the handle for a reorder drag and the drop target that
	/// says where another repository should land. The payload is the repository's path.
	///
	/// Three things here are load-bearing, each established by driving a real drag against a
	/// probe app rather than by reading docs — all of them fail *silently*, with the drag simply
	/// never landing:
	///
	/// - Drag and drop at all, rather than `ForEach.onMove`: a group is a `Section` of the list,
	///   and a plain macOS `List` reorders rows, never sections.
	/// - `onDrag`/`onDrop` rather than `draggable`/`dropDestination`: a section header is not a
	///   drag source for the newer API. It never even starts the drag.
	/// - A declared type — `public.text` — rather than a private one of ours. An *undeclared*
	///   identifier starts a drag that no drop destination will ever match, and declaring one
	///   would mean taking over the target's generated Info.plist. The reducer treats the dropped
	///   string as untrusted anyway: a path that names no tracked repository is ignored, which is
	///   also what makes text dragged in from another app harmless here.
	@ViewBuilder
	func reorderable(
		path: String,
		isEnabled: Bool,
		isTargeted: Binding<Bool>,
		onDrop: @escaping (String) -> Void
	) -> some View {
		if isEnabled {
			onDrag { NSItemProvider(object: path as NSString) }
				.onDrop(of: [.text], isTargeted: isTargeted) { providers in
					guard let provider = providers.first else {
						return false
					}
					// Loaded on the main actor rather than in `loadObject`'s completion handler,
					// which runs off it and so cannot be handed the callback.
					Task { @MainActor in
						let item = try? await provider.loadItem(
							forTypeIdentifier: UTType.utf8PlainText.identifier
						)
						let dragged = (item as? String)
							?? (item as? Data).flatMap { String(data: $0, encoding: .utf8) }
						guard let dragged, dragged != path else {
							return
						}
						onDrop(dragged)
					}
					return true
				}
				// An insertion line rather than a filled highlight: the row underneath already
				// has a background of its own, and the line reads as "it lands here".
				.overlay(alignment: .top) {
					if isTargeted.wrappedValue {
						Rectangle()
							.fill(Color.accentColor)
							.frame(height: 2)
					}
				}
		}
		else {
			self
		}
	}
}

#Preview {
	let mainRow = RepositoryRowReducer.State(
		path: "/projects/myapp",
		name: "myapp",
		branchName: "main",
		isWorktree: false
	)
	let worktreeRow = RepositoryRowReducer.State(
		path: "/worktrees/myapp-feature",
		name: "myapp-feature",
		branchName: "MOB-123_feature",
		isWorktree: true
	)
	List {
		RepoGroupView(
			store: Store(
				initialState: RepoGroupReducer.State(
					id: "/projects/myapp",
					isCollapsed: false,
					header: mainRow,
					worktrees: IdentifiedArrayOf(uniqueElements: [worktreeRow]),
					settings: RepoGroupSettings()
				),
				reducer: { RepoGroupReducer() }
			),
			statusByPath: [:]
		)
	}
	.listStyle(.plain)
}
