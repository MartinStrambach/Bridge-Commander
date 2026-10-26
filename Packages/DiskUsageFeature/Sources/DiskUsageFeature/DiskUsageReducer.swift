import ComposableArchitecture
import Foundation
import Sharing

/// The Disk section: pick a volume or folder, scan it, browse the result as a sunburst and a
/// list, and move what is not wanted to the Trash or delete it.
@Reducer
public struct DiskUsageReducer {
	@ObservableState
	public struct State: Equatable {
		public enum Scan: Equatable {
			case idle
			case scanning(root: URL, progress: DiskScanProgress)
			case finished(DiskScanResult)
		}

		/// An item a batch removal could not remove, for the alert at the end.
		public struct RemovalFailure: Equatable, Sendable {
			public var name: String
			public var error: String

			public init(name: String, error: String) {
				self.name = name
				self.error = error
			}
		}

		/// A result kept for the picker: the tree as the disk was at its `finishedAt`, and the
		/// folder that was on screen when it was left, as names below its root, so Reopen lands
		/// there. Identified by its root's `DiskLocation` key.
		public struct RecentScan: Equatable, Identifiable, Sendable {
			public var result: DiskScanResult
			public var path: [String]

			public init(result: DiskScanResult, path: [String] = []) {
				self.result = result
				self.path = path
			}

			public var id: String { DiskLocation.key(for: result.rootURL) }
		}

		/// How many results the picker keeps to reopen.
		public static let recentScansLimit = 5

		public var volumes: [DiskVolume] = []
		public var scan: Scan = .idle
		/// The nodes from the scan root down to the folder on screen; empty until a scan finishes.
		public var path: [DiskNode] = []
		/// The selected children of the folder on screen, by name, in the order they were
		/// selected: the last is the lead, the one Quick Look shows and the arrow keys move from,
		/// and the first the anchor a shift-click or ⇧↓ extends from.
		public var selectedNames: [String] = []
		/// Whether the selection is shown in Quick Look (Space). Only ever true with a selection:
		/// the panel previews `selectedURL`, so clearing the selection also closes it.
		public var isQuickLookShown = false
		/// The items being removed, while the removal runs.
		public var deletingNames: Set<String> = []
		/// What the running removal could not remove so far; reported once it is over.
		public var removalFailures: [RemovalFailure] = []
		/// Where the last scan started, so Rescan can repeat it after the result is gone.
		public var lastScanRoot: URL?
		/// The results left for the picker, most recent first, one per scan root, so its Reopen
		/// cards bring them back without a scan. A scan of the same root that finishes replaces
		/// the kept one; the list is capped at `recentScansLimit`, since each holds a whole tree.
		public var recentScans: [RecentScan] = []
		/// The folders visited before the one on screen, most recent last, for Back (⌘[). Each is
		/// the names below the scan root, not nodes: a deletion rebuilds the chain, and nodes kept
		/// here would bring the removed item back. A name no longer in the tree stops the walk at
		/// the folder above it.
		public var backHistory: [[String]] = []
		/// The folders left with Back, most recent last, for Forward (⌘]); cleared by any other move.
		public var forwardHistory: [[String]] = []
		/// Folders pinned to the picker, by `DiskLocation.key(for:)`, persisted.
		@Shared(.diskStarredFolders)
		public var starredFolders: [String]
		@Presents
		public var alert: AlertState<Action.Alert>?

		public init() {}

		/// The folder on screen.
		public var currentNode: DiskNode? { path.last }
		/// Where the folder on screen is on disk.
		public var currentURL: URL? { DiskTree.url(of: path) }
		/// The lead of the selection: the item Quick Look shows and the footer names.
		public var selectedName: String? { selectedNames.last }
		public var selectedNode: DiskNode? {
			guard let selectedName else { return nil }
			return currentNode?.child(named: selectedName)
		}
		/// The selected items, in the order they were selected.
		public var selectedNodes: [DiskNode] {
			guard let current = currentNode else { return [] }
			return selectedNames.compactMap { current.child(named: $0) }
		}
		/// Where the lead is on disk; nil for the summed smaller files, which are nowhere.
		public var selectedURL: URL? {
			guard let node = selectedNode, node.isOnDisk else { return nil }
			return DiskTree.url(of: path + [node])
		}
		/// The selected items that can be moved to the Trash or deleted.
		public var removableSelection: [DiskNode] {
			selectedNodes.filter { canRemove($0) }
		}
		public var canGoUp: Bool { path.count > 1 }
		public var canGoBack: Bool { !backHistory.isEmpty }
		public var canGoForward: Bool { !forwardHistory.isEmpty }
		public var isRemoving: Bool { !deletingNames.isEmpty }
		public var isScanning: Bool {
			if case .scanning = scan { return true }
			return false
		}
		public var result: DiskScanResult? {
			if case let .finished(result) = scan { return result }
			return nil
		}
		public var scanRoot: URL? {
			switch scan {
			case .idle: lastScanRoot
			case let .scanning(root, _): root
			case let .finished(result): result.rootURL
			}
		}
		/// Whether the folder on screen is pinned to the picker.
		public var isCurrentFolderStarred: Bool {
			guard let currentURL else { return false }
			return starredFolders.contains(DiskLocation.key(for: currentURL))
		}

		/// Whether a child of the folder on screen is off limits to removal: a folder macOS is
		/// made of, the home folder, a volume, or the scan root (`DiskProtectedLocations`).
		public func isProtected(_ node: DiskNode) -> Bool {
			guard node.isOnDisk, let url = DiskTree.url(of: path + [node]) else { return false }
			return DiskProtectedLocations.isProtected(url, scanRoot: scanRoot, volumes: volumes.map(\.url))
		}

		/// Whether a child of the folder on screen can be moved to the Trash or deleted: one item
		/// on disk that could be read and is not protected.
		public func canRemove(_ node: DiskNode) -> Bool {
			node.isRemovable && !isProtected(node)
		}
	}

	public enum Action: ViewAction {
		case view(View)
		case volumesLoaded([DiskVolume])
		case scanEvent(DiskScanEvent)
		case folderChosen(URL?)
		/// One item of a removal is done, removed from the tree or not.
		case deletionFinished(name: String, error: String?)
		/// Every item of the removal has been tried.
		case removalFinished
		case alert(PresentationAction<Alert>)

		public enum View: Equatable {
			case onAppear
			case scanRequested(URL)
			case chooseFolderTapped
			case rescanTapped
			case stopTapped
			case newScanTapped
			/// A picker's Reopen card: back to a result left with `newScanTapped`, by its root's
			/// `DiskLocation` key.
			case recentScanReopened(String)
			/// Drop a kept result from the picker, by its root's `DiskLocation` key.
			case recentScanRemoved(String)
			/// Drill into a child of the folder on screen.
			case nodeOpened(DiskNode)
			/// Go back to the node at this index of `path`.
			case pathIndexTapped(Int)
			/// To the folder above the one on screen (⌘↑, ←, the chart's centre).
			case goUpTapped
			/// Through the folders visited before (⌘[) and back again (⌘]).
			case goBackTapped
			case goForwardTapped
			/// Select one item alone (a click), or nothing (nil).
			case nodeSelected(String?)
			/// Add an item to the selection or take it out (⌘-click).
			case selectionToggled(String)
			/// Select everything from the anchor to the item (⇧-click).
			case selectionExtended(to: String)
			/// Move the lead through the folder's contents (↑, ↓, Home, End), or with `extending`
			/// grow the selection from the anchor to where the lead lands (⇧↑, ⇧↓).
			case selectionMoved(SelectionMove, extending: Bool = false)
			/// Select every item of the folder on screen (⌘A).
			case selectAllTapped
			/// Open the selected folder (Return, ⌘↓, →).
			case openSelectedTapped
			/// Show the selection in Quick Look, or close the panel if it is open (Space).
			case quickLookToggled
			/// The Quick Look panel moved to another of the folder's items with its arrow keys, or
			/// closed (nil).
			case quickLookItemChanged(URL?)
			case showInFinderTapped
			case moveToTrashTapped
			case deletePermanentlyTapped
			case openFullDiskAccessSettingsTapped
			/// Pin the folder on screen to the picker, or unpin it.
			case starToggled
			/// Unpin a folder from the picker, by its `DiskLocation` key.
			case starredFolderRemoved(String)
		}

		public enum SelectionMove: Equatable, Sendable {
			case previous
			case next
			case first
			case last
		}

		public enum Alert: Equatable {
			case confirmMoveToTrash(names: [String])
			case confirmDelete(names: [String])
		}
	}

	@Dependency(DiskUsageClient.self)
	private var client

	private enum CancelID {
		case scan
	}

	public init() {}

	public var body: some ReducerOf<Self> {
		Reduce { state, action in
			switch action {
			case .view(.onAppear):
				return .run { [client] send in
					await send(.volumesLoaded(client.volumes()))
				}

			case let .volumesLoaded(volumes):
				state.volumes = volumes
				return .none

			case let .view(.scanRequested(root)):
				return startScan(&state, root: root)

			case .view(.chooseFolderTapped):
				return .run { [client] send in
					await send(.folderChosen(client.chooseFolder()))
				}

			case let .folderChosen(url):
				guard let url else { return .none }
				return startScan(&state, root: url)

			case .view(.rescanTapped):
				guard let root = state.scanRoot else { return .none }
				return startScan(&state, root: root)

			case .view(.stopTapped):
				guard state.isScanning else { return .none }
				state.scan = .idle
				return .cancel(id: CancelID.scan)

			case .view(.newScanTapped):
				if let result = state.result {
					keep(&state, State.RecentScan(result: result, path: Self.names(of: state.path)))
				}
				state.scan = .idle
				state.path = []
				deselect(&state)
				clearHistory(&state)
				return .merge(
					.cancel(id: CancelID.scan),
					.run { [client] send in await send(.volumesLoaded(client.volumes())) }
				)

			case let .view(.recentScanReopened(id)):
				guard case .idle = state.scan, let index = state.recentScans.firstIndex(where: { $0.id == id }) else { return .none }
				let recent = state.recentScans.remove(at: index)
				state.scan = .finished(recent.result)
				state.path = Self.resolve(recent.path, from: recent.result.root)
				state.lastScanRoot = recent.result.rootURL
				deselect(&state)
				clearHistory(&state)
				return .none

			case let .view(.recentScanRemoved(id)):
				state.recentScans.removeAll { $0.id == id }
				return .none

			case let .scanEvent(.progress(progress)):
				guard case let .scanning(root, _) = state.scan else { return .none }
				state.scan = .scanning(root: root, progress: progress)
				return .none

			case let .scanEvent(.finished(result)):
				var result = result
				// A volume scan's root adds up to what Finder says is used: the difference is
				// one more child, the hidden space.
				if let volume = result.volume, let hidden = DiskNode.hiddenSpace(for: result.root, on: volume) {
					result.root = DiskNode(directoryNamed: result.root.name, children: result.root.children + [hidden], isInaccessible: result.root.isInaccessible)
				}
				state.scan = .finished(result)
				state.path = [result.root]
				state.recentScans.removeAll { $0.id == DiskLocation.key(for: result.rootURL) }
				deselect(&state)
				clearHistory(&state)
				return .none

			case let .scanEvent(.failed(message)):
				state.scan = .idle
				state.alert = AlertState {
					TextState("Could Not Scan")
				} message: {
					TextState(message)
				}
				return .none

			case let .view(.nodeOpened(node)):
				open(&state, node)
				return .none

			case .view(.openSelectedTapped):
				guard let node = state.selectedNode else { return .none }
				open(&state, node)
				return .none

			case let .view(.pathIndexTapped(index)):
				guard state.path.indices.contains(index), index < state.path.count - 1 else { return .none }
				go(&state, to: Array(state.path[...index]))
				return .none

			case .view(.goUpTapped):
				guard state.canGoUp else { return .none }
				go(&state, to: Array(state.path.dropLast()))
				return .none

			case .view(.goBackTapped):
				walkHistory(&state, from: \.backHistory, to: \.forwardHistory)
				return .none

			case .view(.goForwardTapped):
				walkHistory(&state, from: \.forwardHistory, to: \.backHistory)
				return .none

			case let .view(.nodeSelected(name)):
				if let name {
					state.selectedNames = [name]
				}
				else {
					deselect(&state)
				}
				return .none

			case let .view(.selectionToggled(name)):
				guard state.currentNode?.child(named: name) != nil else { return .none }
				if let index = state.selectedNames.firstIndex(of: name) {
					state.selectedNames.remove(at: index)
					if state.selectedNames.isEmpty {
						deselect(&state)
					}
				}
				else {
					state.selectedNames.append(name)
				}
				return .none

			case let .view(.selectionExtended(name)):
				extendSelection(&state, to: name)
				return .none

			case let .view(.selectionMoved(move, extending)):
				guard let children = state.currentNode?.children, !children.isEmpty else { return .none }
				let index = state.selectedName.flatMap { name in children.firstIndex { $0.name == name } }
				let target = switch (move, index) {
				case (.first, _), (.next, nil): 0
				case (.last, _), (.previous, nil): children.count - 1
				case let (.next, index?): min(index + 1, children.count - 1)
				case let (.previous, index?): max(index - 1, 0)
				}
				if extending {
					extendSelection(&state, to: children[target].name)
				}
				else {
					state.selectedNames = [children[target].name]
				}
				return .none

			case .view(.selectAllTapped):
				guard let children = state.currentNode?.children, !children.isEmpty else { return .none }
				state.selectedNames = children.map(\.name)
				return .none

			case .view(.quickLookToggled):
				guard state.selectedURL != nil else { return .none }
				state.isQuickLookShown.toggle()
				return .none

			case let .view(.quickLookItemChanged(url)):
				guard let url else {
					state.isQuickLookShown = false
					return .none
				}
				// The panel only knows URLs; the one it moved to is a child of the folder on screen.
				if let child = state.currentNode?.children.first(where: { DiskTree.url(of: state.path + [$0]) == url }) {
					state.selectedNames = [child.name]
				}
				return .none

			case .view(.showInFinderTapped):
				guard let url = state.selectedURL else { return .none }
				return .run { [client] _ in client.showInFinder(url) }

			case .view(.moveToTrashTapped):
				let nodes = state.removableSelection
				guard !nodes.isEmpty, !state.isRemoving else { return .none }
				state.alert = Self.moveToTrashAlert(for: nodes)
				return .none

			case .view(.deletePermanentlyTapped):
				let nodes = state.removableSelection
				guard !nodes.isEmpty, !state.isRemoving else { return .none }
				state.alert = Self.deleteAlert(for: nodes)
				return .none

			case .view(.openFullDiskAccessSettingsTapped):
				return .run { [client] _ in client.openFullDiskAccessSettings() }

			case .view(.starToggled):
				guard let url = state.currentURL else { return .none }
				let key = DiskLocation.key(for: url)
				state.$starredFolders.withLock { starred in
					if let index = starred.firstIndex(of: key) {
						starred.remove(at: index)
					}
					else {
						starred.append(key)
					}
				}
				return .none

			case let .view(.starredFolderRemoved(key)):
				state.$starredFolders.withLock { $0.removeAll { $0 == key } }
				return .none

			case let .alert(.presented(.confirmMoveToTrash(names))):
				return remove(&state, names: names) { [client] in try await client.moveToTrash($0) }

			case let .alert(.presented(.confirmDelete(names))):
				return remove(&state, names: names) { [client] in try await client.deletePermanently($0) }

			case .alert:
				return .none

			case let .deletionFinished(name, error):
				state.deletingNames.remove(name)
				if let error {
					state.removalFailures.append(.init(name: name, error: error))
					return .none
				}
				guard state.currentNode?.child(named: name) != nil else { return .none }
				state.path = DiskTree.removing(childNamed: name, from: state.path)
				state.selectedNames.removeAll { $0 == name }
				if state.selectedNames.isEmpty {
					deselect(&state)
				}
				if case let .finished(result) = state.scan, let root = state.path.first {
					var updated = result
					updated.root = root
					state.scan = .finished(updated)
				}
				return .none

			case .removalFinished:
				state.deletingNames = []
				let failures = state.removalFailures
				state.removalFailures = []
				guard !failures.isEmpty else { return .none }
				state.alert = Self.removalFailedAlert(failures)
				return .none
			}
		}
		.ifLet(\.$alert, action: \.alert)
	}

	private func startScan(_ state: inout State, root: URL) -> Effect<Action> {
		state.scan = .scanning(root: root, progress: DiskScanProgress())
		state.path = []
		deselect(&state)
		clearHistory(&state)
		state.lastScanRoot = root
		return .run { [client] send in
			for await event in client.scan(root) {
				await send(.scanEvent(event))
			}
		}
		.cancellable(id: CancelID.scan, cancelInFlight: true)
	}

	/// Into a folder of the one on screen; a file or an unreadable folder is not opened.
	private func open(_ state: inout State, _ node: DiskNode) {
		guard node.isDirectory, !node.isInaccessible, let current = state.currentNode, current.children.contains(where: { $0 === node }) else {
			return
		}
		go(&state, to: state.path + [node])
	}

	/// Shows `path`, remembering the folder left for Back; a new move forgets what Forward had.
	private func go(_ state: inout State, to path: [DiskNode]) {
		guard path != state.path else { return }
		state.backHistory.append(Self.names(of: state.path))
		state.forwardHistory = []
		show(&state, path)
	}

	/// Back or Forward: shows the latest entry of one history, moving the folder left onto the
	/// other. An entry that now resolves to the folder on screen (its folder was removed) is
	/// dropped and the next one tried, so the key never seems to do nothing.
	private func walkHistory(_ state: inout State, from source: WritableKeyPath<State, [[String]]>, to destination: WritableKeyPath<State, [[String]]>) {
		guard let root = state.path.first else { return }
		while let names = state[keyPath: source].popLast() {
			let path = Self.resolve(names, from: root)
			guard path != state.path else { continue }
			state[keyPath: destination].append(Self.names(of: state.path))
			show(&state, path)
			return
		}
	}

	/// Puts `path` on screen. Coming back up, the folder just left is selected, so ↓/↑ carry on
	/// from it and Return goes straight back in; going down nothing is. Quick Look closes either
	/// way: it was showing an item of the folder left.
	private func show(_ state: inout State, _ path: [DiskNode]) {
		let left = state.path
		state.path = path
		deselect(&state)
		if left.count > path.count, Array(left.prefix(path.count)) == path {
			state.selectedNames = [left[path.count].name]
		}
	}

	/// Selects everything between the anchor (the first item selected) and `name`, in the list's
	/// order from the anchor, so `name` becomes the lead. With nothing selected, `name` alone.
	private func extendSelection(_ state: inout State, to name: String) {
		guard let children = state.currentNode?.children, let target = children.firstIndex(where: { $0.name == name }) else { return }
		guard let anchorName = state.selectedNames.first, let anchor = children.firstIndex(where: { $0.name == anchorName }) else {
			state.selectedNames = [name]
			return
		}
		let range = anchor <= target ? Array(anchor ... target) : Array(target ... anchor).reversed()
		state.selectedNames = range.map { children[$0].name }
	}

	/// Clears the selection, and with it the Quick Look panel, which has nothing left to show.
	private func deselect(_ state: inout State) {
		state.selectedNames = []
		state.isQuickLookShown = false
	}

	private func clearHistory(_ state: inout State) {
		state.backHistory = []
		state.forwardHistory = []
	}

	/// Puts a result at the front of the picker's recent scans, in place of any kept for the
	/// same root, and drops the oldest past the limit.
	private func keep(_ state: inout State, _ recent: State.RecentScan) {
		state.recentScans.removeAll { $0.id == recent.id }
		state.recentScans.insert(recent, at: 0)
		if state.recentScans.count > State.recentScansLimit {
			state.recentScans.removeLast(state.recentScans.count - State.recentScansLimit)
		}
	}

	private static func names(of path: [DiskNode]) -> [String] {
		path.dropFirst().map(\.name)
	}

	/// The chain from `root` down the named folders, as far as they are still in the tree.
	private static func resolve(_ names: [String], from root: DiskNode) -> [DiskNode] {
		var path = [root]
		for name in names {
			guard let child = path[path.count - 1].child(named: name), child.isDirectory, !child.isInaccessible else { break }
			path.append(child)
		}
		return path
	}

	/// Removes the named children of the folder on screen one after another, those that can be
	/// removed, reporting each as it is done and the failures together at the end.
	private func remove(_ state: inout State, names: [String], using operation: @escaping @Sendable (URL) async throws -> Void) -> Effect<Action> {
		let targets = names.compactMap { name -> (name: String, url: URL)? in
			guard let node = state.currentNode?.child(named: name), state.canRemove(node), let url = DiskTree.url(of: state.path + [node]) else {
				return nil
			}
			return (name, url)
		}
		guard !targets.isEmpty else { return .none }
		state.deletingNames = Set(targets.map(\.name))
		state.removalFailures = []
		return .run { send in
			for target in targets {
				do {
					try await operation(target.url)
					await send(.deletionFinished(name: target.name, error: nil))
				}
				catch {
					await send(.deletionFinished(name: target.name, error: error.localizedDescription))
				}
			}
			await send(.removalFinished)
		}
	}

	static func moveToTrashAlert(for nodes: [DiskNode]) -> AlertState<Action.Alert> {
		AlertState {
			TextState(nodes.count == 1 ? "Move “\(nodes[0].name)” to the Trash?" : "Move \(nodes.count.formatted()) Items to the Trash?")
		} actions: {
			ButtonState(role: .destructive, action: .confirmMoveToTrash(names: nodes.map(\.name))) {
				TextState("Move to Trash")
			}
			ButtonState(role: .cancel) {
				TextState("Cancel")
			}
		} message: {
			TextState("\(Self.describe(nodes)) will be moved to the Trash. The space is freed once the Trash is emptied.")
		}
	}

	static func deleteAlert(for nodes: [DiskNode]) -> AlertState<Action.Alert> {
		AlertState {
			TextState(nodes.count == 1 ? "Delete “\(nodes[0].name)” Permanently?" : "Delete \(nodes.count.formatted()) Items Permanently?")
		} actions: {
			ButtonState(role: .destructive, action: .confirmDelete(names: nodes.map(\.name))) {
				TextState("Delete")
			}
			ButtonState(role: .cancel) {
				TextState("Cancel")
			}
		} message: {
			TextState("\(Self.describe(nodes)) will be deleted right away. This cannot be undone.")
		}
	}

	static func removalFailedAlert(_ failures: [State.RemovalFailure]) -> AlertState<Action.Alert> {
		AlertState {
			TextState(failures.count == 1 ? "Could Not Remove “\(failures[0].name)”" : "Could Not Remove \(failures.count.formatted()) Items")
		} message: {
			TextState(failures.count == 1 ? failures[0].error : failures.map { "\($0.name): \($0.error)" }.joined(separator: "\n"))
		}
	}

	/// "A folder of 2 GB (1,234 items)", "A file of 3 MB", or for several "3 items of 2.5 GB".
	private static func describe(_ nodes: [DiskNode]) -> String {
		let size = nodes.reduce(Int64(0)) { $0 + $1.size }.formatted(.byteCount(style: .file))
		guard nodes.count == 1, let node = nodes.first else {
			return "\(nodes.count.formatted()) items of \(size)"
		}
		switch node.kind {
		case .directory:
			return "A folder of \(size) (\(node.itemCount.formatted()) items)"
		case .file, .smallerFiles, .hiddenSpace:
			return "A file of \(size)"
		}
	}
}
