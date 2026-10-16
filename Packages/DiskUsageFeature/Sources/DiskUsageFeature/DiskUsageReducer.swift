import ComposableArchitecture
import Foundation

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

		public var volumes: [DiskVolume] = []
		public var scan: Scan = .idle
		/// The nodes from the scan root down to the folder on screen; empty until a scan finishes.
		public var path: [DiskNode] = []
		/// The child of the folder on screen that is selected, by name.
		public var selectedName: String?
		/// Whether the selection is shown in Quick Look (Space). Only ever true with a selection:
		/// the panel previews `selectedURL`, so clearing the selection also closes it.
		public var isQuickLookShown = false
		/// The folder or file being removed, while the removal runs.
		public var deletingName: String?
		/// Where the last scan started, so Rescan can repeat it after the result is gone.
		public var lastScanRoot: URL?
		/// The folders visited before the one on screen, most recent last, for Back (⌘[). Each is
		/// the names below the scan root, not nodes: a deletion rebuilds the chain, and nodes kept
		/// here would bring the removed item back. A name no longer in the tree stops the walk at
		/// the folder above it.
		public var backHistory: [[String]] = []
		/// The folders left with Back, most recent last, for Forward (⌘]); cleared by any other move.
		public var forwardHistory: [[String]] = []
		@Presents
		public var alert: AlertState<Action.Alert>?

		public init() {}

		/// The folder on screen.
		public var currentNode: DiskNode? { path.last }
		public var selectedNode: DiskNode? {
			guard let selectedName else { return nil }
			return currentNode?.child(named: selectedName)
		}
		/// Where the selection is on disk; nil for the summed smaller files, which are nowhere.
		public var selectedURL: URL? {
			guard let node = selectedNode, node.isOnDisk else { return nil }
			return DiskTree.url(of: path + [node])
		}
		public var canGoUp: Bool { path.count > 1 }
		public var canGoBack: Bool { !backHistory.isEmpty }
		public var canGoForward: Bool { !forwardHistory.isEmpty }
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
	}

	public enum Action: ViewAction {
		case view(View)
		case volumesLoaded([DiskVolume])
		case scanEvent(DiskScanEvent)
		case folderChosen(URL?)
		case deletionFinished(name: String, error: String?)
		case alert(PresentationAction<Alert>)

		public enum View: Equatable {
			case onAppear
			case scanRequested(URL)
			case chooseFolderTapped
			case rescanTapped
			case stopTapped
			case newScanTapped
			/// Drill into a child of the folder on screen.
			case nodeOpened(DiskNode)
			/// Go back to the node at this index of `path`.
			case pathIndexTapped(Int)
			/// To the folder above the one on screen (⌘↑, ←, the chart's centre).
			case goUpTapped
			/// Through the folders visited before (⌘[) and back again (⌘]).
			case goBackTapped
			case goForwardTapped
			case nodeSelected(String?)
			/// Move the selection through the folder's contents (↑, ↓, Home, End).
			case selectionMoved(SelectionMove)
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
		}

		public enum SelectionMove: Equatable, Sendable {
			case previous
			case next
			case first
			case last
		}

		public enum Alert: Equatable {
			case confirmMoveToTrash(name: String)
			case confirmDelete(name: String)
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
				state.scan = .idle
				state.path = []
				deselect(&state)
				clearHistory(&state)
				return .merge(
					.cancel(id: CancelID.scan),
					.run { [client] send in await send(.volumesLoaded(client.volumes())) }
				)

			case let .scanEvent(.progress(progress)):
				guard case let .scanning(root, _) = state.scan else { return .none }
				state.scan = .scanning(root: root, progress: progress)
				return .none

			case let .scanEvent(.finished(result)):
				state.scan = .finished(result)
				state.path = [result.root]
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
					state.selectedName = name
				}
				else {
					deselect(&state)
				}
				return .none

			case let .view(.selectionMoved(move)):
				guard let children = state.currentNode?.children, !children.isEmpty else { return .none }
				let index = state.selectedName.flatMap { name in children.firstIndex { $0.name == name } }
				let target = switch (move, index) {
				case (.first, _), (.next, nil): 0
				case (.last, _), (.previous, nil): children.count - 1
				case let (.next, index?): min(index + 1, children.count - 1)
				case let (.previous, index?): max(index - 1, 0)
				}
				state.selectedName = children[target].name
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
					state.selectedName = child.name
				}
				return .none

			case .view(.showInFinderTapped):
				guard let url = state.selectedURL else { return .none }
				return .run { [client] _ in client.showInFinder(url) }

			case .view(.moveToTrashTapped):
				guard let node = state.selectedNode, node.isRemovable else { return .none }
				state.alert = Self.moveToTrashAlert(for: node)
				return .none

			case .view(.deletePermanentlyTapped):
				guard let node = state.selectedNode, node.isRemovable else { return .none }
				state.alert = Self.deleteAlert(for: node)
				return .none

			case .view(.openFullDiskAccessSettingsTapped):
				return .run { [client] _ in client.openFullDiskAccessSettings() }

			case let .alert(.presented(.confirmMoveToTrash(name))):
				return remove(&state, name: name) { [client] in try await client.moveToTrash($0) }

			case let .alert(.presented(.confirmDelete(name))):
				return remove(&state, name: name) { [client] in try await client.deletePermanently($0) }

			case .alert:
				return .none

			case let .deletionFinished(name, error):
				state.deletingName = nil
				if let error {
					state.alert = AlertState {
						TextState("Could Not Remove “\(name)”")
					} message: {
						TextState(error)
					}
					return .none
				}
				guard state.currentNode?.child(named: name) != nil else { return .none }
				state.path = DiskTree.removing(childNamed: name, from: state.path)
				if state.selectedName == name {
					deselect(&state)
				}
				if case let .finished(result) = state.scan, let root = state.path.first {
					var updated = result
					updated.root = root
					state.scan = .finished(updated)
				}
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
			state.selectedName = left[path.count].name
		}
	}

	/// Clears the selection, and with it the Quick Look panel, which has nothing left to show.
	private func deselect(_ state: inout State) {
		state.selectedName = nil
		state.isQuickLookShown = false
	}

	private func clearHistory(_ state: inout State) {
		state.backHistory = []
		state.forwardHistory = []
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

	private func remove(_ state: inout State, name: String, using operation: @escaping @Sendable (URL) async throws -> Void) -> Effect<Action> {
		guard let node = state.currentNode?.child(named: name), let url = DiskTree.url(of: state.path + [node]) else {
			return .none
		}
		state.deletingName = name
		return .run { send in
			do {
				try await operation(url)
				await send(.deletionFinished(name: name, error: nil))
			}
			catch {
				await send(.deletionFinished(name: name, error: error.localizedDescription))
			}
		}
	}

	static func moveToTrashAlert(for node: DiskNode) -> AlertState<Action.Alert> {
		AlertState {
			TextState("Move “\(node.name)” to the Trash?")
		} actions: {
			ButtonState(role: .destructive, action: .confirmMoveToTrash(name: node.name)) {
				TextState("Move to Trash")
			}
			ButtonState(role: .cancel) {
				TextState("Cancel")
			}
		} message: {
			TextState("\(Self.describe(node)) will be moved to the Trash. The space is freed once the Trash is emptied.")
		}
	}

	static func deleteAlert(for node: DiskNode) -> AlertState<Action.Alert> {
		AlertState {
			TextState("Delete “\(node.name)” Permanently?")
		} actions: {
			ButtonState(role: .destructive, action: .confirmDelete(name: node.name)) {
				TextState("Delete")
			}
			ButtonState(role: .cancel) {
				TextState("Cancel")
			}
		} message: {
			TextState("\(Self.describe(node)) will be deleted right away. This cannot be undone.")
		}
	}

	private static func describe(_ node: DiskNode) -> String {
		let size = node.size.formatted(.byteCount(style: .file))
		switch node.kind {
		case .directory:
			return "A folder of \(size) (\(node.itemCount.formatted()) items)"
		case .file, .smallerFiles:
			return "A file of \(size)"
		}
	}
}
