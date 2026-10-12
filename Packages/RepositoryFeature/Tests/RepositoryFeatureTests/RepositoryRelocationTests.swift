import ComposableArchitecture
import Foundation
import GitCore
import Settings
import Testing
import TerminalFeature
import ToolsIntegration
@testable import RepositoryFeature

// A tracked repository is known by its path everywhere: the tracked list, its settings, its
// collapsed state, its terminals. When its folder is renamed or moved, all of that follows it;
// when the folder is gone, the repository stays tracked and is listed as missing.
@Suite("Renamed, moved and missing repositories")
@MainActor
struct RepositoryRelocationTests {
	@Test("a moved repository keeps its place, settings, collapsed state, bookmark and terminals")
	func movedRepositoryTakesItsStateAlong() async {
		let session = TerminalSession(repositoryPath: "/repos/alpha/worktrees/one")
		var initialState = RepositoryListReducer.State()
		initialState.terminalSessions = [session]
		initialState.terminalLayout = TerminalLayoutReducer.State(activeRepositoryPath: "/repos/alpha")
		let store = makeStore(initialState)
		await addRepositories(["/repos/alpha", "/repos/beta"], to: store)
		store.state.$groupSettings.withLock { $0["/repos/alpha"] = RepoGroupSettings(supportsIOS: true) }
		store.state.$collapsedRepoPaths.withLock { $0 = ["/repos/alpha", "/repos/beta"] }
		store.state.$trackedRepoBookmarks.withLock { $0["/repos/alpha"] = Data([0]) }

		await store.send(.trackedRepositoryMoved(from: "/repos/alpha", to: "/repos/zeta", bookmark: Data([1])))

		#expect(store.state.trackedRepoPaths == ["/repos/zeta", "/repos/beta"])
		#expect(store.state.repositoryGroups.map(\.id) == ["/repos/beta"])
		#expect(store.state.groupSettings == ["/repos/zeta": RepoGroupSettings(supportsIOS: true)])
		#expect(store.state.collapsedRepoPaths == ["/repos/beta", "/repos/zeta"])
		#expect(store.state.trackedRepoBookmarks == ["/repos/zeta": Data([1])])
		#expect(store.state.terminalSessions[id: session.id]?.repositoryPath == "/repos/zeta/worktrees/one")
		#expect(store.state.terminalLayout?.activeRepositoryPath == "/repos/zeta")

		// The scan that follows builds the group again, in the place the old one had.
		await store.send(.didScanGroup(rootPath: "/repos/zeta", rows: [mainRepo("/repos/zeta")]))
		#expect(store.state.repositoryGroups.map(\.id) == ["/repos/zeta", "/repos/beta"])
		await store.finish()
	}

	@Test("a repository moved onto one tracked already is tracked once")
	func movedOntoTrackedPathDropsOldEntry() async {
		let store = makeStore()
		await addRepositories(["/repos/alpha", "/repos/beta"], to: store)

		await store.send(.trackedRepositoryMoved(from: "/repos/alpha", to: "/repos/beta", bookmark: nil))

		#expect(store.state.trackedRepoPaths == ["/repos/beta"])
		#expect(store.state.repositoryGroups.map(\.id) == ["/repos/beta"])
		await store.finish()
	}

	@Test("a repository whose folder is gone stays tracked and is listed missing until found")
	func missingRepositoryIsListed() async {
		let store = makeStore(location: { path, _ in path == "/repos/alpha" ? .missing : .present(bookmark: nil) })
		await addRepositories(["/repos/alpha", "/repos/beta"], to: store)

		await store.send(.startScan)
		await store.receive(\.trackedRepositoryMissing)
		await store.receive(\.scanCompleted)

		#expect(store.state.trackedRepoPaths == ["/repos/alpha", "/repos/beta"])
		#expect(store.state.missingRepoPaths == ["/repos/alpha"])
		#expect(!store.state.repositoryGroups.ids.contains("/repos/alpha"))

		// Back again, say on a volume mounted later.
		await store.send(.didScanGroup(rootPath: "/repos/alpha", rows: [mainRepo("/repos/alpha")]))
		#expect(store.state.missingRepoPaths.isEmpty)
		#expect(store.state.repositoryGroups.map(\.id) == ["/repos/alpha", "/repos/beta"])
		await store.finish()
	}

	@Test("Remove on a missing repository forgets it")
	func removingMissingRepositoryForgetsIt() async {
		let store = makeStore(location: { _, _ in .missing })
		await addRepositories(["/repos/alpha"], to: store)
		store.state.$trackedRepoBookmarks.withLock { $0["/repos/alpha"] = Data([0]) }
		await store.send(.trackedRepositoryMissing("/repos/alpha"))

		await store.send(.view(.missingRepositoryRemoveButtonTapped("/repos/alpha")))

		#expect(store.state.trackedRepoPaths.isEmpty)
		#expect(store.state.missingRepoPaths.isEmpty)
		#expect(store.state.trackedRepoBookmarks.isEmpty)
		await store.finish()
	}

	@Test("a folder renamed on disk rescans its group")
	func locationChangeRescansGroup() async {
		let (changes, continuation) = AsyncStream<[GitRepositoryChange]>.makeStream()
		let store = makeStore(changes: changes, location: { _, _ in .missing })
		await addRepositories(["/repos/alpha"], to: store)
		await store.send(.scanCompleted)

		continuation.yield([GitRepositoryChange(repositoryPath: "/repos/alpha", kinds: .location)])
		await store.receive(\.repositoriesChangedOnDisk)
		await store.receive(\.trackedRepositoryMissing)

		#expect(store.state.missingRepoPaths == ["/repos/alpha"])
		await store.send(.view(.onDisappear))
		await store.finish()
	}

	@Test("a repository renamed on disk is followed there, end to end")
	func renamedRepositoryIsFollowed() async throws {
		let directory = try temporaryDirectory()
		defer { try? FileManager.default.removeItem(atPath: directory) }
		let oldPath = directory + "/pandemonium"
		let newPath = directory + "/bejeweled"
		try FileManager.default.createDirectory(atPath: oldPath, withIntermediateDirectories: false)
		try git(["init", "--quiet"], at: oldPath)
		let store = makeStore(locationClient: .liveValue)

		await store.send(.addRepository(oldPath))
		await store.receive(\.addRepositorySucceeded)
		await store.receive(\.trackedRepositoryBookmarked)
		#expect(store.state.trackedRepoBookmarks[oldPath] != nil)

		try FileManager.default.moveItem(atPath: oldPath, toPath: newPath)
		await store.send(.startScan)
		await store.receive(\.trackedRepositoryMoved)
		await store.receive(\.didScanGroup)
		await store.receive(\.scanCompleted)

		#expect(store.state.trackedRepoPaths == [newPath])
		#expect(store.state.repositoryGroups.map(\.id) == [newPath])
		#expect(store.state.trackedRepoBookmarks.keys.sorted() == [newPath])
		#expect(store.state.missingRepoPaths.isEmpty)
		await store.send(.view(.onDisappear))
		await store.finish()
	}

	// MARK: - Helpers

	/// Non-exhaustive: the rows a new group builds fan out into effects of their own.
	private func makeStore(
		_ initialState: RepositoryListReducer.State = RepositoryListReducer.State(),
		changes: AsyncStream<[GitRepositoryChange]> = AsyncStream { $0.finish() },
		location: @escaping @Sendable (String, Data?) -> RepositoryLocation = { _, _ in .present(bookmark: nil) },
		locationClient: RepositoryLocationClient? = nil
	) -> TestStoreOf<RepositoryListReducer> {
		let store = TestStore(initialState: initialState) {
			RepositoryListReducer()
		} withDependencies: {
			// Keeps `trackedRepoPaths` and the rest off the user's own files in Application Support.
			$0.defaultFileStorage = .inMemory
			$0[GitRepositoryWatcherClient.self].changes = { _ in changes }
			$0[RepositoryLocationClient.self].locate = location
			if let locationClient {
				$0[RepositoryLocationClient.self] = locationClient
			}
			$0[GitClient.self].getCurrentBranch = { _ in
				GitPorcelainStatus(parsing: "", didSucceed: false)
			}
			$0[XcodeClient.self].findXcodeProject = { _, _, _ in nil }
			$0[LastOpenedDirectoryClient.self].load = { nil }
		}
		store.exhaustivity = .off
		return store
	}

	private func addRepositories(_ paths: [String], to store: TestStoreOf<RepositoryListReducer>) async {
		for path in paths {
			await store.send(.addRepositorySucceeded(rootPath: path, scanned: [mainRepo(path)]))
		}
	}

	private func mainRepo(_ path: String) -> ScannedRepository {
		ScannedRepository(
			path: path,
			name: (path as NSString).lastPathComponent,
			directory: path,
			isWorktree: false,
			branchName: "main"
		)
	}

	/// A fresh folder, by the path the list tracks it under: standardized, so `/var/…` rather
	/// than the `/private/var/…` git reports.
	private func temporaryDirectory() throws -> String {
		let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
		return url.standardizedFileURL.path
	}

	private func git(_ arguments: [String], at path: String) throws {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
		process.arguments = arguments
		process.currentDirectoryURL = URL(fileURLWithPath: path)
		try process.run()
		process.waitUntilExit()
	}
}
