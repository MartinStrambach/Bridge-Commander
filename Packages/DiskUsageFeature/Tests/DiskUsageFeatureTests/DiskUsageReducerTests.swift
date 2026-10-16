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

	/// Six files a to f, largest first.
	private static func wideResult() -> DiskScanResult {
		let files = ["a", "b", "c", "d", "e", "f"].enumerated().map { index, name in
			DiskNode(name: name, kind: .file, size: Int64(600 - index * 100), itemCount: 1)
		}
		let root = DiskNode(directoryNamed: rootURL.path(percentEncoded: false), children: files)
		return DiskScanResult(root: root, rootURL: rootURL, inaccessibleFolders: 0, duration: .seconds(1))
	}

	private func scannedStore(result: DiskScanResult = Self.result(), trashed: LockIsolated<[URL]> = .init([])) async -> TestStoreOf<DiskUsageReducer> {
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
			$0[DiskUsageClient.self].volumes = { [] }
		}
		await store.send(.view(.scanRequested(Self.rootURL))) {
			$0.scan = .scanning(root: Self.rootURL, progress: DiskScanProgress())
			$0.lastScanRoot = Self.rootURL
		}
		await store.receive(\.scanEvent.progress) {
			$0.scan = .scanning(root: Self.rootURL, progress: DiskScanProgress(scannedBytes: 10, scannedItems: 1))
		}
		store.exhaustivity = .off(showSkippedAssertions: false)
		await store.receive(\.scanEvent.finished)
		store.exhaustivity = .on
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
			$0.selectedNames = ["Cache"]
			$0.backHistory = [[], ["Cache"]]
		}
	}

	@Test("the arrow keys walk the selection and Return opens it")
	func keyboardSelection() async {
		let store = await scannedStore()
		let cache = store.state.currentNode!.child(named: "Cache")!

		await store.send(.view(.selectionMoved(.next))) {
			$0.selectedNames = ["Cache"]
		}
		await store.send(.view(.selectionMoved(.next))) {
			$0.selectedNames = ["notes.md"]
		}
		// The last item stays selected rather than wrapping round.
		await store.send(.view(.selectionMoved(.next)))
		await store.send(.view(.selectionMoved(.first))) {
			$0.selectedNames = ["Cache"]
		}
		await store.send(.view(.openSelectedTapped)) {
			$0.path.append(cache)
			$0.selectedNames = []
			$0.backHistory = [[]]
		}
		// Nothing selected: ↑ starts from the end.
		await store.send(.view(.selectionMoved(.previous))) {
			$0.selectedNames = ["big.bin"]
		}
		// A file is not opened.
		await store.send(.view(.openSelectedTapped))
		await store.send(.view(.goUpTapped)) {
			$0.path.removeLast()
			$0.selectedNames = ["Cache"]
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
			$0.selectedNames = ["Cache"]
			$0.backHistory = []
			$0.forwardHistory = [["Cache"]]
		}
		await store.send(.view(.goForwardTapped)) {
			$0.path = [root, cache]
			$0.selectedNames = []
			$0.backHistory = [[]]
			$0.forwardHistory = []
		}
		await store.send(.view(.goBackTapped)) {
			$0.path = [root]
			$0.selectedNames = ["Cache"]
			$0.backHistory = []
			$0.forwardHistory = [["Cache"]]
		}
		await store.send(.view(.nodeOpened(cache))) {
			$0.path = [root, cache]
			$0.selectedNames = []
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
			$0.selectedNames = ["Cache"]
			$0.backHistory = [[], ["Cache"]]
		}
		store.exhaustivity = .off(showSkippedAssertions: false)
		await store.send(.view(.moveToTrashTapped))
		await store.send(.alert(.presented(.confirmMoveToTrash(names: ["Cache"]))))
		await store.receive(\.deletionFinished)
		await store.receive(\.removalFinished)
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
		#expect(DiskKeyboard.action(for: .space, modifiers: [], hasSelection: true) == .quickLookToggled)
		// Escape and Space with nothing selected are left to the window.
		#expect(DiskKeyboard.action(for: .escape, modifiers: [], hasSelection: false) == nil)
		#expect(DiskKeyboard.action(for: .space, modifiers: [], hasSelection: false) == nil)
		#expect(DiskKeyboard.action(for: .downArrow, modifiers: .shift, hasSelection: false) == .selectionMoved(.next, extending: true))
		#expect(DiskKeyboard.action(for: .upArrow, modifiers: [.shift, .numericPad], hasSelection: true) == .selectionMoved(.previous, extending: true))
		#expect(DiskKeyboard.action(for: "a", modifiers: .command, hasSelection: false) == .selectAllTapped)
		#expect(DiskKeyboard.action(for: "a", modifiers: [], hasSelection: false) == nil)
	}

	@Test("Space shows the selection in Quick Look, the panel's arrows move the selection, and leaving the folder closes it")
	func quickLook() async {
		let store = await scannedStore()
		let cache = store.state.currentNode!.child(named: "Cache")!

		// Nothing selected, nothing to show.
		await store.send(.view(.quickLookToggled))
		await store.send(.view(.nodeSelected("Cache"))) {
			$0.selectedNames = ["Cache"]
		}
		await store.send(.view(.quickLookToggled)) {
			$0.isQuickLookShown = true
		}
		#expect(store.state.selectedURL == Self.rootURL.appending(path: "Cache", directoryHint: .isDirectory))

		await store.send(.view(.quickLookItemChanged(Self.rootURL.appending(path: "notes.md", directoryHint: .notDirectory)))) {
			$0.selectedNames = ["notes.md"]
		}
		// A URL that is not one of the folder's items is ignored.
		await store.send(.view(.quickLookItemChanged(URL(filePath: "/elsewhere"))))
		await store.send(.view(.quickLookItemChanged(nil))) {
			$0.isQuickLookShown = false
		}

		await store.send(.view(.quickLookToggled)) {
			$0.isQuickLookShown = true
		}
		await store.send(.view(.quickLookToggled)) {
			$0.isQuickLookShown = false
		}
		await store.send(.view(.quickLookToggled)) {
			$0.isQuickLookShown = true
		}
		await store.send(.view(.nodeSelected("Cache"))) {
			$0.selectedNames = ["Cache"]
		}
		await store.send(.view(.openSelectedTapped)) {
			$0.path.append(cache)
			$0.selectedNames = []
			$0.isQuickLookShown = false
			$0.backHistory = [[]]
		}
	}

	@Test("moving the selection to the Trash asks first, then takes it out of the tree")
	func moveToTrash() async {
		let trashed = LockIsolated<[URL]>([])
		let store = await scannedStore(trashed: trashed)
		let cache = store.state.currentNode!.child(named: "Cache")!

		await store.send(.view(.nodeSelected("Cache"))) {
			$0.selectedNames = ["Cache"]
		}
		await store.send(.view(.moveToTrashTapped)) {
			$0.alert = DiskUsageReducer.moveToTrashAlert(for: [cache])
		}
		await store.send(.alert(.presented(.confirmMoveToTrash(names: ["Cache"])))) {
			$0.alert = nil
			$0.deletingNames = ["Cache"]
		}
		// Nodes are compared by identity, so the rebuilt chain cannot be spelled out here.
		store.exhaustivity = .off(showSkippedAssertions: false)
		await store.receive(\.deletionFinished)
		await store.receive(\.removalFinished)
		#expect(trashed.value.map { $0.path(percentEncoded: false) } == ["/Volumes/Data/Cache/"])
		#expect(store.state.deletingNames.isEmpty)
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
			$0.selectedNames = ["notes.md"]
		}
		await store.send(.view(.deletePermanentlyTapped)) {
			$0.alert = DiskUsageReducer.deleteAlert(for: [store.state.selectedNode!])
		}
		await store.send(.alert(.presented(.confirmDelete(names: ["notes.md"])))) {
			$0.alert = nil
			$0.deletingNames = ["notes.md"]
		}
		await store.receive(\.deletionFinished) {
			$0.deletingNames = []
			$0.removalFailures = [.init(name: "notes.md", error: "Operation not permitted")]
		}
		await store.receive(\.removalFinished) {
			$0.removalFailures = []
			$0.alert = AlertState {
				TextState("Could Not Remove “notes.md”")
			} message: {
				TextState("Operation not permitted")
			}
		}
		#expect(store.state.currentNode?.children.count == 2)
		#expect(store.state.selectedName == "notes.md")
	}

	@Test("⌘-click, ⇧-click and ⇧↓ build a selection; the anchor stays first and the lead last")
	func multiSelection() async {
		let store = await scannedStore(result: Self.wideResult())

		await store.send(.view(.nodeSelected("b"))) {
			$0.selectedNames = ["b"]
		}
		await store.send(.view(.selectionToggled("d"))) {
			$0.selectedNames = ["b", "d"]
		}
		// A name that is not in the folder is ignored.
		await store.send(.view(.selectionToggled("nope")))
		await store.send(.view(.selectionToggled("b"))) {
			$0.selectedNames = ["d"]
		}
		// ⇧-click above the anchor: from the anchor up to the item, the item last.
		await store.send(.view(.selectionExtended(to: "a"))) {
			$0.selectedNames = ["d", "c", "b", "a"]
		}
		// ⇧↓ moves the lead and re-extends from the anchor.
		await store.send(.view(.selectionMoved(.next, extending: true))) {
			$0.selectedNames = ["d", "c", "b"]
		}
		await store.send(.view(.selectionMoved(.next, extending: true))) {
			$0.selectedNames = ["d", "c"]
		}
		await store.send(.view(.selectionMoved(.next, extending: true))) {
			$0.selectedNames = ["d"]
		}
		await store.send(.view(.selectionMoved(.next, extending: true))) {
			$0.selectedNames = ["d", "e"]
		}
		// A plain ↓ collapses to the lead's neighbour.
		await store.send(.view(.selectionMoved(.next))) {
			$0.selectedNames = ["f"]
		}
		await store.send(.view(.selectAllTapped)) {
			$0.selectedNames = ["a", "b", "c", "d", "e", "f"]
		}
		#expect(store.state.selectedName == "f")
		// Taking the last one out closes Quick Look with the selection.
		await store.send(.view(.nodeSelected("a"))) {
			$0.selectedNames = ["a"]
		}
		await store.send(.view(.quickLookToggled)) {
			$0.isQuickLookShown = true
		}
		await store.send(.view(.selectionToggled("a"))) {
			$0.selectedNames = []
			$0.isQuickLookShown = false
		}
	}

	@Test("several selected items are removed one after another, with one confirmation")
	func batchRemoval() async {
		let trashed = LockIsolated<[URL]>([])
		let store = await scannedStore(result: Self.wideResult(), trashed: trashed)
		let nodes = store.state.currentNode!.children

		await store.send(.view(.selectAllTapped)) {
			$0.selectedNames = ["a", "b", "c", "d", "e", "f"]
		}
		await store.send(.view(.moveToTrashTapped)) {
			$0.alert = DiskUsageReducer.moveToTrashAlert(for: nodes)
		}
		await store.send(.alert(.presented(.confirmMoveToTrash(names: nodes.map(\.name))))) {
			$0.alert = nil
			$0.deletingNames = ["a", "b", "c", "d", "e", "f"]
		}
		store.exhaustivity = .off(showSkippedAssertions: false)
		for _ in nodes {
			await store.receive(\.deletionFinished)
		}
		await store.receive(\.removalFinished)
		#expect(trashed.value.map(\.lastPathComponent) == ["a", "b", "c", "d", "e", "f"])
		#expect(store.state.currentNode?.children.isEmpty == true)
		#expect(store.state.selectedNames.isEmpty)
		#expect(store.state.deletingNames.isEmpty)
		#expect(store.state.alert == nil)
	}

	@Test("a batch reports every failure together at the end and keeps the rest of the tree")
	func batchRemovalFailures() async {
		struct Refused: LocalizedError {
			var errorDescription: String? { "Operation not permitted" }
		}
		let store = await scannedStore(result: Self.wideResult())
		store.dependencies[DiskUsageClient.self].deletePermanently = { url in
			if url.lastPathComponent != "b" { throw Refused() }
		}

		await store.send(.view(.nodeSelected("a"))) {
			$0.selectedNames = ["a"]
		}
		await store.send(.view(.selectionExtended(to: "c"))) {
			$0.selectedNames = ["a", "b", "c"]
		}
		store.exhaustivity = .off(showSkippedAssertions: false)
		await store.send(.view(.deletePermanentlyTapped))
		await store.send(.alert(.presented(.confirmDelete(names: ["a", "b", "c"]))))
		await store.receive(\.deletionFinished)
		await store.receive(\.deletionFinished)
		await store.receive(\.deletionFinished)
		await store.receive(\.removalFinished)
		#expect(store.state.currentNode?.children.map(\.name) == ["a", "c", "d", "e", "f"])
		#expect(store.state.selectedNames == ["a", "c"])
		#expect(store.state.alert == DiskUsageReducer.removalFailedAlert([
			.init(name: "a", error: "Operation not permitted"),
			.init(name: "c", error: "Operation not permitted"),
		]))
	}

	@Test("system folders, the home folder and volumes cannot be removed")
	func protectedLocations() async {
		let home = FileManager.default.homeDirectoryForCurrentUser
		let library = DiskNode(directoryNamed: "Library", children: [DiskNode(name: "x", kind: .file, size: 1, itemCount: 1)])
		let users = DiskNode(directoryNamed: "Users", children: [DiskNode(directoryNamed: home.lastPathComponent, children: [library])])
		let system = DiskNode(directoryNamed: "System", children: [DiskNode(name: "y", kind: .file, size: 2, itemCount: 1)])
		let projects = DiskNode(directoryNamed: "Projects", children: [DiskNode(name: "z", kind: .file, size: 3, itemCount: 1)])
		let root = DiskNode(directoryNamed: "/", children: [users, system, projects])
		let result = DiskScanResult(root: root, rootURL: URL(filePath: "/"), inaccessibleFolders: 0, duration: .seconds(1))
		let store = await scannedStore(result: result)

		#expect(!store.state.canRemove(system))
		#expect(!store.state.canRemove(users))
		#expect(store.state.canRemove(projects))
		#expect(store.state.isProtected(system))
		#expect(!store.state.isProtected(projects))

		// Protected items are left out of the removal, and nothing is asked when none is left.
		await store.send(.view(.selectAllTapped)) {
			$0.selectedNames = ["Projects", "System", "Users"]
		}
		#expect(store.state.removableSelection.map(\.name) == ["Projects"])
		await store.send(.view(.nodeSelected("System"))) {
			$0.selectedNames = ["System"]
		}
		await store.send(.view(.moveToTrashTapped))
		await store.send(.view(.deletePermanentlyTapped))

		// The home folder and its Library, in any scan.
		await store.send(.view(.nodeOpened(users))) {
			$0.path.append(users)
			$0.selectedNames = []
			$0.backHistory = [[]]
		}
		let me = store.state.currentNode!.children[0]
		#expect(store.state.isProtected(me))
		await store.send(.view(.nodeOpened(me))) {
			$0.path.append(me)
			$0.backHistory = [[], ["Users"]]
		}
		#expect(store.state.isProtected(store.state.currentNode!.child(named: "Library")!))
	}

	@Test("the pure protection check knows the system folders, the home folder, volumes and the scan root")
	func protectionCheck() {
		let home = URL(filePath: "/Users/me", directoryHint: .isDirectory)
		let volumes = [URL(filePath: "/"), URL(filePath: "/Volumes/Backup/")]
		func protected(_ path: String, scanRoot: String? = nil) -> Bool {
			DiskProtectedLocations.isProtected(URL(filePath: path), scanRoot: scanRoot.map { URL(filePath: $0) }, volumes: volumes, home: home)
		}
		#expect(protected("/System"))
		#expect(protected("/Library/"))
		#expect(protected("/private/var"))
		#expect(protected("/Users/me"))
		#expect(protected("/Users/me/Library"))
		#expect(protected("/Volumes/Backup"))
		#expect(protected("/Users/me/Projects", scanRoot: "/Users/me/Projects/"))
		#expect(!protected("/Users/me/Projects"))
		#expect(!protected("/Users/me/Library/Caches"))
		#expect(!protected("/Users/other"))
		#expect(!protected("/Library/Caches"))
	}

	@Test("a volume scan gets a hidden-space child for what the volume reports beyond the scan")
	func hiddenSpace() async {
		var result = Self.result()
		result.volume = DiskVolumeUsage(allocatedCapacity: 1000, purgeableCapacity: 100, otherVolumesCapacity: 50)
		let store = await scannedStore(result: result)
		let root = store.state.currentNode!

		#expect(root.size == 1000)
		#expect(root.children.map(\.name) == ["Cache", DiskNode.hiddenSpaceName, "notes.md"])
		let hidden = root.child(named: DiskNode.hiddenSpaceName)!
		#expect(hidden.size == 350)
		#expect(hidden.kind == .hiddenSpace(purgeable: 100, otherVolumes: 50))
		#expect(!hidden.isOnDisk)
		#expect(!store.state.canRemove(hidden))
		#expect(DiskNodeDescription.hiddenSpaceBreakdown(size: 350, purgeable: 100, otherVolumes: 50) == "100 bytes purgeable, 50 bytes other volumes, 200 bytes unreadable or file system data")

		// Selecting it shows nothing in Quick Look and opens nothing.
		await store.send(.view(.nodeSelected(DiskNode.hiddenSpaceName))) {
			$0.selectedNames = [DiskNode.hiddenSpaceName]
		}
		#expect(store.state.selectedURL == nil)
		await store.send(.view(.quickLookToggled))
		await store.send(.view(.openSelectedTapped))

		// A removal keeps it, and the root shrinks by the removed item only.
		store.exhaustivity = .off(showSkippedAssertions: false)
		await store.send(.view(.nodeSelected("Cache")))
		await store.send(.view(.moveToTrashTapped))
		await store.send(.alert(.presented(.confirmMoveToTrash(names: ["Cache"]))))
		await store.receive(\.removalFinished)
		#expect(store.state.currentNode?.size == 400)
		#expect(store.state.currentNode?.children.map(\.name) == [DiskNode.hiddenSpaceName, "notes.md"])
	}

	@Test("a scan with no volume behind it or nothing hidden adds no hidden space")
	func noHiddenSpace() async {
		var result = Self.result()
		result.volume = DiskVolumeUsage(allocatedCapacity: 650, purgeableCapacity: 0, otherVolumesCapacity: 0)
		let store = await scannedStore(result: result)
		#expect(store.state.currentNode?.children.map(\.name) == ["Cache", "notes.md"])
		let other = await scannedStore()
		#expect(other.state.currentNode?.children.map(\.name) == ["Cache", "notes.md"])
	}

	@Test("the star pins the folder on screen to the picker and unpins it; the picker can unpin too")
	func starredFolders() async {
		let store = await scannedStore()
		let cache = store.state.currentNode!.child(named: "Cache")!
		#expect(store.state.starredFolders.isEmpty)
		#expect(!store.state.isCurrentFolderStarred)

		await store.send(.view(.starToggled)) {
			$0.$starredFolders.withLock { $0 = ["/Volumes/Data"] }
		}
		#expect(store.state.isCurrentFolderStarred)
		await store.send(.view(.nodeOpened(cache))) {
			$0.path.append(cache)
			$0.backHistory = [[]]
		}
		#expect(!store.state.isCurrentFolderStarred)
		await store.send(.view(.starToggled)) {
			$0.$starredFolders.withLock { $0 = ["/Volumes/Data", "/Volumes/Data/Cache"] }
		}
		await store.send(.view(.starToggled)) {
			$0.$starredFolders.withLock { $0 = ["/Volumes/Data"] }
		}
		await store.send(.view(.starredFolderRemoved("/Volumes/Data"))) {
			$0.$starredFolders.withLock { $0 = [] }
		}
		#expect(DiskLocation.url(forKey: "/Volumes/Data/Cache").path(percentEncoded: false) == "/Volumes/Data/Cache/")
	}

	@Test("leaving for the picker keeps the result, and Reopen brings it back to the folder left")
	func reopenLastResult() async {
		let store = await scannedStore()
		let result = store.state.result!
		let cache = result.root.child(named: "Cache")!
		await store.send(.view(.nodeOpened(cache))) {
			$0.path = [result.root, cache]
			$0.backHistory = [[]]
		}
		await store.send(.view(.newScanTapped)) {
			$0.scan = .idle
			$0.path = []
			$0.backHistory = []
			$0.lastResult = result
			$0.lastResultPath = ["Cache"]
		}
		await store.receive(\.volumesLoaded)
		await store.send(.view(.lastResultReopened)) {
			$0.scan = .finished(result)
			$0.path = [result.root, cache]
			$0.lastResult = nil
			$0.lastResultPath = []
		}
		#expect(store.state.currentNode === cache)

		// A scan that finishes replaces the kept result; a stopped one leaves it there.
		await store.send(.view(.newScanTapped)) {
			$0.scan = .idle
			$0.path = []
			$0.lastResult = result
			$0.lastResultPath = ["Cache"]
		}
		await store.receive(\.volumesLoaded)
		store.exhaustivity = .off(showSkippedAssertions: false)
		await store.send(.view(.scanRequested(Self.rootURL)))
		await store.receive(\.scanEvent.finished)
		store.exhaustivity = .on
		#expect(store.state.lastResult == nil)
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
