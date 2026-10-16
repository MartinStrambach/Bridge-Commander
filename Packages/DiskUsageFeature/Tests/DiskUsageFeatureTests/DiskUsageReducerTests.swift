import ComposableArchitecture
import Foundation
import SwiftUI
import Testing
@testable import DiskUsageFeature

@Suite("Disk usage")
@MainActor
struct DiskUsageReducerTests {
	private static let rootURL = URL(filePath: "/Volumes/Data", directoryHint: .isDirectory)

	private static func result() -> DiskScanResult {
		let big = DiskNode(name: "big.bin", kind: .file, size: 600, itemCount: 1)
		let cache = DiskNode(directoryNamed: "Cache", children: [big])
		let notes = DiskNode(name: "notes.md", kind: .file, size: 50, itemCount: 1)
		let root = DiskNode(directoryNamed: rootURL.path(percentEncoded: false), children: [cache, notes])
		return DiskScanResult(root: root, rootURL: rootURL, inaccessibleFolders: 0, duration: .seconds(1))
	}

	private func scannedStore(trashed: LockIsolated<[URL]> = .init([])) async -> TestStoreOf<DiskUsageReducer> {
		let result = Self.result()
		let store = TestStore(initialState: DiskUsageReducer.State()) {
			DiskUsageReducer()
		} withDependencies: {
			$0[DiskUsageClient.self].scan = { _ in
				AsyncStream { continuation in
					continuation.yield(.progress(DiskScanProgress(scannedBytes: 10, scannedItems: 1)))
					continuation.yield(.finished(result))
					continuation.finish()
				}
			}
			$0[DiskUsageClient.self].moveToTrash = { url in trashed.withValue { $0.append(url) } }
		}
		await store.send(.view(.scanRequested(Self.rootURL))) {
			$0.scan = .scanning(root: Self.rootURL, progress: DiskScanProgress())
			$0.lastScanRoot = Self.rootURL
		}
		await store.receive(\.scanEvent.progress) {
			$0.scan = .scanning(root: Self.rootURL, progress: DiskScanProgress(scannedBytes: 10, scannedItems: 1))
		}
		await store.receive(\.scanEvent.finished) {
			$0.scan = .finished(result)
			$0.path = [result.root]
		}
		return store
	}

	@Test("a scan streams progress and ends on the root folder")
	func scanFlow() async {
		let store = await scannedStore()
		#expect(store.state.currentNode?.children.map(\.name) == ["Cache", "notes.md"])
	}

	@Test("opening a folder and the breadcrumb move through the tree")
	func navigation() async {
		let store = await scannedStore()
		let cache = store.state.currentNode!.child(named: "Cache")!

		await store.send(.view(.nodeOpened(cache))) {
			$0.path.append(cache)
			$0.backHistory = [[]]
		}
		// A file is not opened.
		await store.send(.view(.nodeOpened(cache.children[0])))
		await store.send(.view(.pathIndexTapped(0))) {
			$0.path.removeLast()
			$0.selectedName = "Cache"
			$0.backHistory = [[], ["Cache"]]
		}
	}

	@Test("the arrow keys walk the selection and Return opens it")
	func keyboardSelection() async {
		let store = await scannedStore()
		let cache = store.state.currentNode!.child(named: "Cache")!

		await store.send(.view(.selectionMoved(.next))) {
			$0.selectedName = "Cache"
		}
		await store.send(.view(.selectionMoved(.next))) {
			$0.selectedName = "notes.md"
		}
		// The last item stays selected rather than wrapping round.
		await store.send(.view(.selectionMoved(.next)))
		await store.send(.view(.selectionMoved(.first))) {
			$0.selectedName = "Cache"
		}
		await store.send(.view(.openSelectedTapped)) {
			$0.path.append(cache)
			$0.selectedName = nil
			$0.backHistory = [[]]
		}
		// Nothing selected: ↑ starts from the end.
		await store.send(.view(.selectionMoved(.previous))) {
			$0.selectedName = "big.bin"
		}
		// A file is not opened.
		await store.send(.view(.openSelectedTapped))
		await store.send(.view(.goUpTapped)) {
			$0.path.removeLast()
			$0.selectedName = "Cache"
			$0.backHistory = [[], ["Cache"]]
		}
		// At the root there is nothing above.
		await store.send(.view(.goUpTapped))
	}

	@Test("back and forward walk the folders visited, and a new move forgets forward")
	func history() async {
		let store = await scannedStore()
		let root = store.state.path[0]
		let cache = root.child(named: "Cache")!

		await store.send(.view(.goBackTapped))
		await store.send(.view(.nodeOpened(cache))) {
			$0.path = [root, cache]
			$0.backHistory = [[]]
		}
		await store.send(.view(.goBackTapped)) {
			$0.path = [root]
			$0.selectedName = "Cache"
			$0.backHistory = []
			$0.forwardHistory = [["Cache"]]
		}
		await store.send(.view(.goForwardTapped)) {
			$0.path = [root, cache]
			$0.selectedName = nil
			$0.backHistory = [[]]
			$0.forwardHistory = []
		}
		await store.send(.view(.goBackTapped)) {
			$0.path = [root]
			$0.selectedName = "Cache"
			$0.backHistory = []
			$0.forwardHistory = [["Cache"]]
		}
		await store.send(.view(.nodeOpened(cache))) {
			$0.path = [root, cache]
			$0.selectedName = nil
			$0.backHistory = [[]]
			$0.forwardHistory = []
		}
	}

	@Test("a history entry whose folder was removed is skipped")
	func historyAfterRemoval() async {
		let store = await scannedStore()
		let cache = store.state.currentNode!.child(named: "Cache")!

		await store.send(.view(.nodeOpened(cache))) {
			$0.path.append(cache)
			$0.backHistory = [[]]
		}
		await store.send(.view(.goUpTapped)) {
			$0.path.removeLast()
			$0.selectedName = "Cache"
			$0.backHistory = [[], ["Cache"]]
		}
		store.exhaustivity = .off(showSkippedAssertions: false)
		await store.send(.view(.moveToTrashTapped))
		await store.send(.alert(.presented(.confirmMoveToTrash(name: "Cache"))))
		await store.receive(\.deletionFinished)
		#expect(store.state.currentNode?.child(named: "Cache") == nil)

		// Back would land on Cache, now gone, which resolves to the root on screen: skipped, and
		// with nothing before it Back stays put.
		await store.send(.view(.goBackTapped))
		#expect(store.state.path.count == 1)
		#expect(store.state.backHistory.isEmpty)
		#expect(store.state.forwardHistory.isEmpty)
	}

	@Test("keys map to the map's actions; the arrow keys' numeric-pad flag does not count")
	func keyMapping() {
		#expect(DiskKeyboard.action(for: .downArrow, modifiers: .numericPad, hasSelection: false) == .selectionMoved(.next))
		#expect(DiskKeyboard.action(for: .upArrow, modifiers: .command, hasSelection: false) == .goUpTapped)
		#expect(DiskKeyboard.action(for: .downArrow, modifiers: .command, hasSelection: false) == .openSelectedTapped)
		#expect(DiskKeyboard.action(for: .return, modifiers: [], hasSelection: true) == .openSelectedTapped)
		#expect(DiskKeyboard.action(for: .leftArrow, modifiers: [], hasSelection: true) == .goUpTapped)
		#expect(DiskKeyboard.action(for: .escape, modifiers: [], hasSelection: true) == .nodeSelected(nil))
		// Escape with nothing selected is left to the window.
		#expect(DiskKeyboard.action(for: .escape, modifiers: [], hasSelection: false) == nil)
		#expect(DiskKeyboard.action(for: .downArrow, modifiers: .shift, hasSelection: false) == nil)
	}

	@Test("moving the selection to the Trash asks first, then takes it out of the tree")
	func moveToTrash() async {
		let trashed = LockIsolated<[URL]>([])
		let store = await scannedStore(trashed: trashed)
		let cache = store.state.currentNode!.child(named: "Cache")!

		await store.send(.view(.nodeSelected("Cache"))) {
			$0.selectedName = "Cache"
		}
		await store.send(.view(.moveToTrashTapped)) {
			$0.alert = DiskUsageReducer.moveToTrashAlert(for: cache)
		}
		await store.send(.alert(.presented(.confirmMoveToTrash(name: "Cache")))) {
			$0.alert = nil
			$0.deletingName = "Cache"
		}
		// Nodes are compared by identity, so the rebuilt chain cannot be spelled out here.
		store.exhaustivity = .off(showSkippedAssertions: false)
		await store.receive(\.deletionFinished)
		#expect(trashed.value.map { $0.path(percentEncoded: false) } == ["/Volumes/Data/Cache/"])
		#expect(store.state.deletingName == nil)
		#expect(store.state.selectedName == nil)
		#expect(store.state.path.count == 1)
		#expect(store.state.currentNode?.children.map(\.name) == ["notes.md"])
		#expect(store.state.currentNode?.size == 50)
		#expect(store.state.result?.root === store.state.path[0])
	}

	@Test("a failed removal reports and leaves the tree alone")
	func failedRemoval() async {
		struct Refused: LocalizedError {
			var errorDescription: String? { "Operation not permitted" }
		}
		let store = await scannedStore()
		store.dependencies[DiskUsageClient.self].deletePermanently = { _ in throw Refused() }

		await store.send(.view(.nodeSelected("notes.md"))) {
			$0.selectedName = "notes.md"
		}
		await store.send(.view(.deletePermanentlyTapped)) {
			$0.alert = DiskUsageReducer.deleteAlert(for: store.state.selectedNode!)
		}
		await store.send(.alert(.presented(.confirmDelete(name: "notes.md")))) {
			$0.alert = nil
			$0.deletingName = "notes.md"
		}
		await store.receive(\.deletionFinished) {
			$0.deletingName = nil
			$0.alert = AlertState {
				TextState("Could Not Remove “notes.md”")
			} message: {
				TextState("Operation not permitted")
			}
		}
		#expect(store.state.currentNode?.children.count == 2)
	}

	@Test("stopping a scan cancels it and goes back to the picker")
	func stopScan() async {
		let store = TestStore(initialState: DiskUsageReducer.State()) {
			DiskUsageReducer()
		} withDependencies: {
			$0[DiskUsageClient.self].scan = { _ in AsyncStream { _ in } }
		}
		await store.send(.view(.scanRequested(Self.rootURL))) {
			$0.scan = .scanning(root: Self.rootURL, progress: DiskScanProgress())
			$0.lastScanRoot = Self.rootURL
		}
		await store.send(.view(.stopTapped)) {
			$0.scan = .idle
		}
	}
}
