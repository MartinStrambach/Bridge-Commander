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
		/// The folder or file being removed, while the removal runs.
		public var deletingName: String?
		/// Where the last scan started, so Rescan can repeat it after the result is gone.
		public var lastScanRoot: URL?
		@Presents
		public var alert: AlertState<Action.Alert>?

		public init() {}

		/// The folder on screen.
		public var currentNode: DiskNode? { path.last }
		public var selectedNode: DiskNode? {
			guard let selectedName else { return nil }
			return currentNode?.child(named: selectedName)
		}
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

		public enum View {
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
			case nodeSelected(String?)
			case showInFinderTapped
			case moveToTrashTapped
			case deletePermanentlyTapped
			case openFullDiskAccessSettingsTapped
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
				state.selectedName = nil
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
				state.selectedName = nil
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
				guard node.isDirectory, !node.isInaccessible, let current = state.currentNode, current.children.contains(where: { $0 === node }) else {
					return .none
				}
				state.path.append(node)
				state.selectedName = nil
				return .none

			case let .view(.pathIndexTapped(index)):
				guard state.path.indices.contains(index) else { return .none }
				let opened = state.path.indices.contains(index + 1) ? state.path[index + 1].name : nil
				state.path.removeSubrange((index + 1)...)
				// Coming back up, the folder just left is the natural selection.
				state.selectedName = opened
				return .none

			case let .view(.nodeSelected(name)):
				state.selectedName = name
				return .none

			case .view(.showInFinderTapped):
				guard let url = selectedURL(state) else { return .none }
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
					state.selectedName = nil
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
		state.selectedName = nil
		state.lastScanRoot = root
		return .run { [client] send in
			for await event in client.scan(root) {
				await send(.scanEvent(event))
			}
		}
		.cancellable(id: CancelID.scan, cancelInFlight: true)
	}

	private func selectedURL(_ state: State) -> URL? {
		guard let node = state.selectedNode, node.isOnDisk else { return nil }
		return DiskTree.url(of: state.path + [node])
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
