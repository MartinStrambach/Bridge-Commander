import ComposableArchitecture
import Foundation
import GitCore
import TerminalFeature
import Testing
import ToolsIntegration
@testable import RepositoryFeature

// Scans overlap with each other and with what the user does meanwhile: a worktree removed from its
// row is rescanned away by the file system watch while the removal is still finishing, a scan
// lands after its group was removed, a repository is added twice before the first add is done.
@Suite("Repository scan races")
@MainActor
struct RepositoryScanRaceTests {
	// MARK: - Rows a scan drops

	@Test("a row a scan drops has its running effects cancelled")
	func droppedRowEffectsAreCancelled() async {
		let store = makeStore(statusFetch: { path in
			// The worktree's `git status` answers only once cancelled, as a killed process would.
			if path == "/repos/alpha-one" {
				while !Task.isCancelled {
					try? await Task.sleep(for: .milliseconds(10))
				}
			}
			return GitPorcelainStatus(parsing: "", didSucceed: false)
		})
		await scanAlpha(withWorktree: true, in: store)
		await store.send(.repositoryGroups(.element(
			id: "/repos/alpha",
			action: .worktrees(.element(id: "/repos/alpha-one", action: .refresh))
		)))

		await scanAlpha(withWorktree: false, in: store)

		#expect(store.state.repositoryGroups[id: "/repos/alpha"]?.worktrees.isEmpty == true)
		// Left running, the fetch would never end, and would land on a row that is gone. Exhaustive,
		// or a fetch still running at the end would pass unreported.
		store.exhaustivity = .on
		await store.finish(timeout: .seconds(2))
	}

	@Test("a scan that no longer lists a worktree closes its terminal tabs")
	func droppedWorktreeClosesItsTabs() async {
		let store = makeStore()
		await scanAlpha(withWorktree: true, in: store)
		await store.send(.repositoryGroups(.element(
			id: "/repos/alpha",
			action: .worktrees(.element(id: "/repos/alpha-one", action: .openTerminalForRepo))
		)))
		#expect(store.state.terminalSessions.map(\.repositoryPath) == ["/repos/alpha-one"])

		// The watch's rescan after `git worktree remove` can beat the row's own report of it.
		await scanAlpha(withWorktree: false, in: store)

		#expect(store.state.terminalSessions.isEmpty)
		#expect(store.state.terminalLayout == nil)
		await store.finish()
	}

	@Test("a failed scan keeps the rows, and the tabs, it did not list")
	func failedScanKeepsTabs() async {
		let store = makeStore()
		await scanAlpha(withWorktree: true, in: store)
		await store.send(.repositoryGroups(.element(
			id: "/repos/alpha",
			action: .worktrees(.element(id: "/repos/alpha-one", action: .openTerminalForRepo))
		)))

		await store.send(.didScanGroup(rootPath: "/repos/alpha", rows: []))

		#expect(store.state.repositoryGroups[id: "/repos/alpha"]?.worktrees.map(\.id) == ["/repos/alpha-one"])
		#expect(store.state.terminalSessions.count == 1)
		await store.finish()
	}

	@Test("a cleanup that left something behind is reported by the list, not the row")
	func removalWarningShowsOnTheList() async {
		let store = makeStore()
		store.exhaustivity = .on

		await store.send(.worktreeRemovedWithWarnings("branch kept")) {
			$0.alert = AlertState {
				TextState("Worktree Removed")
			} actions: {
				ButtonState(role: .cancel, action: .dismiss) { TextState("OK") }
			} message: {
				TextState("Worktree was removed successfully, but:\n\nbranch kept")
			}
		}
	}

	// MARK: - Removed groups

	@Test("a scan landing after Clear does not bring its group back")
	func scanAfterClearIsIgnored() async {
		let store = makeStore()
		await scanAlpha(withWorktree: false, in: store)

		await store.send(.view(.clearButtonTapped))
		await scanAlpha(withWorktree: false, in: store)

		#expect(store.state.repositoryGroups.isEmpty)
		await store.finish()
	}

	@Test("a scan landing after its group was removed does not bring it back")
	func scanAfterRemoveIsIgnored() async {
		let store = makeStore()
		await scanAlpha(withWorktree: false, in: store)

		await store.send(.repositoryGroups(.element(id: "/repos/alpha", action: .remove)))
		await scanAlpha(withWorktree: false, in: store)

		#expect(store.state.repositoryGroups.isEmpty)
		await store.finish()
	}

	@Test("Clear leaves the periodic refresh running for the repositories added next")
	func clearKeepsPeriodicRefresh() async {
		let store = makeStore()

		await store.send(.startPeriodicRefresh)
		await store.send(.view(.clearButtonTapped))

		// Strict: fails when nothing is left running.
		await store.skipInFlightEffects(strict: true)
	}

	// MARK: - Duplicates

	@Test("a repository whose add finishes twice is tracked once")
	func doubleAddTracksOnce() async {
		let store = makeStore()
		let scanned = [mainRepo("/repos/alpha")]

		await store.send(.addRepositorySucceeded(rootPath: "/repos/alpha", scanned: scanned))
		await store.send(.addRepositorySucceeded(rootPath: "/repos/alpha", scanned: scanned))

		#expect(store.state.trackedRepoPaths == ["/repos/alpha"])
		#expect(store.state.repositoryGroups.map(\.id) == ["/repos/alpha"])
		await store.finish()
	}

	@Test("a repository tracked twice by an older version still loads")
	func persistedDuplicateDoesNotTrap() async {
		let store = makeStore()
		store.state.$trackedRepoPaths.withLock {
			$0 = ["/repos/alpha", "/repos/beta", "/repos/alpha"]
		}

		await store.send(.didScanGroup(rootPath: "/repos/beta", rows: [mainRepo("/repos/beta")]))
		await store.send(.didScanGroup(rootPath: "/repos/alpha", rows: [mainRepo("/repos/alpha")]))

		#expect(store.state.repositoryGroups.map(\.id) == ["/repos/alpha", "/repos/beta"])
		await store.finish()
	}

	// MARK: - Helpers

	private func makeStore(
		statusFetch: @escaping @Sendable (String) async -> GitPorcelainStatus = { _ in
			GitPorcelainStatus(parsing: "", didSucceed: false)
		}
	) -> TestStoreOf<RepositoryListReducer> {
		let store = TestStore(initialState: RepositoryListReducer.State()) {
			RepositoryListReducer()
		} withDependencies: {
			// `trackedRepoPaths` is file-backed; keep it off the user's real list.
			$0.defaultFileStorage = .inMemory
			// A failed status short-circuits the row's YouTrack and PR follow-ups.
			$0[GitClient.self].getCurrentBranch = statusFetch
			$0[XcodeClient.self].findXcodeProject = { _, _, _ in nil }
			$0[GitRepositoryWatcherClient.self].changes = { _ in AsyncStream { $0.finish() } }
		}
		store.exhaustivity = .off
		store.track("/repos/alpha")
		return store
	}

	private func scanAlpha(withWorktree: Bool, in store: TestStoreOf<RepositoryListReducer>) async {
		var rows = [mainRepo("/repos/alpha")]
		if withWorktree {
			rows.append(ScannedRepository(
				path: "/repos/alpha-one",
				name: "alpha-one",
				directory: "/repos/alpha-one",
				isWorktree: true,
				branchName: "feature-one"
			))
		}
		await store.send(.didScanGroup(rootPath: "/repos/alpha", rows: rows))
		// A rescan's rows reach the group in an action of its own (`applyScannedRows`).
		await store.skipReceivedActions(strict: false)
	}

	private func mainRepo(_ path: String) -> ScannedRepository {
		ScannedRepository(
			path: path,
			name: (path as NSString).lastPathComponent,
			directory: path,
			isWorktree: false,
			branchName: "master"
		)
	}
}
