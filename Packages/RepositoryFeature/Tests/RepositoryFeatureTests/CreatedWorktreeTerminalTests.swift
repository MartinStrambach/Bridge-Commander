import ComposableArchitecture
import Foundation
import GitCore
import Settings
import TerminalFeature
import Testing
import ToolsIntegration
@testable import RepositoryFeature

// A worktree created with a terminal follow-up has no row until a scan finds it, so the list
// remembers the follow-up and opens the built-in terminal from the scan that brings the row in.
@Suite("Terminal for a newly created worktree")
@MainActor
struct CreatedWorktreeTerminalTests {
	@Test("running Claude opens the new worktree's first tab with the Claude command, not the group's")
	func claudeOpensOnceScanned() async {
		let store = makeStore(groupCommand: "mise install")
		await scanAlpha(store, worktrees: [])

		await store.send(created("/repos/alpha-new", launch: .command("claude 'Work on MOB-1'")))
		#expect(store.state.terminalSessions.isEmpty)

		await scanAlpha(store, worktrees: ["/repos/alpha-new"])
		#expect(store.state.terminalSessions.map(\.repositoryPath) == ["/repos/alpha-new"])
		#expect(store.state.terminalSessions.map(\.startupCommand) == ["claude 'Work on MOB-1'"])
		#expect(store.state.terminalLayout?.activeRepositoryPath == "/repos/alpha-new")
		#expect(store.state.pendingWorktreeLaunches.isEmpty)
	}

	@Test("opening the terminal alone keeps the group's startup command")
	func terminalKeepsGroupCommand() async {
		let store = makeStore(groupCommand: "mise install")
		await scanAlpha(store, worktrees: [])

		await store.send(created("/repos/alpha-new", launch: .terminal))
		await scanAlpha(store, worktrees: ["/repos/alpha-new"])

		#expect(store.state.terminalSessions.map(\.startupCommand) == ["mise install"])
	}

	@Test("without a follow-up nothing opens")
	func noFollowUpOpensNothing() async {
		let store = makeStore(groupCommand: "")
		await scanAlpha(store, worktrees: [])

		await store.send(created("/repos/alpha-new", launch: nil))
		await scanAlpha(store, worktrees: ["/repos/alpha-new"])

		#expect(store.state.terminalSessions.isEmpty)
		#expect(store.state.terminalLayout == nil)
	}

	@Test("a scan that does not have the worktree yet keeps waiting; the follow-up runs only once")
	func waitsForTheRightScan() async {
		let store = makeStore(groupCommand: "")
		await scanAlpha(store, worktrees: [])

		await store.send(created("/repos/alpha-new", launch: .command("claude")))
		await scanAlpha(store, worktrees: ["/repos/alpha-other"])
		#expect(store.state.terminalSessions.isEmpty)

		await scanAlpha(store, worktrees: ["/repos/alpha-other", "/repos/alpha-new"])
		await scanAlpha(store, worktrees: ["/repos/alpha-other", "/repos/alpha-new"])
		#expect(store.state.terminalSessions.map(\.repositoryPath) == ["/repos/alpha-new"])
	}

	@Test("the creator's path and git's realpath meet")
	func matchesThroughSymlinks() async throws {
		let root = FileManager.default.temporaryDirectory
			.appending(component: "created-worktree-\(UUID().uuidString)")
		let real = root.appending(component: "real")
		let link = root.appending(component: "link")
		try FileManager.default.createDirectory(at: real.appending(component: "wt"), withIntermediateDirectories: true)
		try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
		defer { try? FileManager.default.removeItem(at: root) }

		let store = makeStore(groupCommand: "")
		await scanAlpha(store, worktrees: [])
		await store.send(created(link.appending(component: "wt").path, launch: .command("claude")))
		await scanAlpha(store, worktrees: [real.appending(component: "wt").path])

		#expect(store.state.terminalSessions.count == 1)
	}

	// MARK: - Helpers

	private func makeStore(groupCommand: String) -> TestStoreOf<RepositoryListReducer> {
		@Shared(.groupSettings) var groupSettings: [String: RepoGroupSettings] = [:]
		$groupSettings.withLock {
			$0 = ["/repos/alpha": RepoGroupSettings(terminalStartupCommand: groupCommand)]
		}
		let store = TestStore(initialState: RepositoryListReducer.State()) {
			RepositoryListReducer()
		} withDependencies: {
			$0[GitClient.self].getCurrentBranch = { _ in
				GitPorcelainStatus(parsing: "", didSucceed: false)
			}
			$0[XcodeClient.self].findXcodeProject = { _, _, _ in nil }
			$0[LastOpenedDirectoryClient.self].load = { nil }
		}
		store.exhaustivity = .off
		return store
	}

	/// The header row reports the creation, as it does for the dialog on a group's root row.
	private func created(_ path: String, launch: WorktreeTerminalLaunch?) -> RepositoryListReducer.Action {
		.repositoryGroups(.element(id: "/repos/alpha", action: .header(.worktreeCreated(path: path, launch: launch))))
	}

	private func scanAlpha(_ store: TestStoreOf<RepositoryListReducer>, worktrees: [String]) async {
		await store.send(.didScanGroup(
			rootPath: "/repos/alpha",
			rows: [scanned("/repos/alpha", isWorktree: false)] + worktrees.map { scanned($0, isWorktree: true) }
		))
	}

	private func scanned(_ path: String, isWorktree: Bool) -> ScannedRepository {
		ScannedRepository(
			path: path,
			name: (path as NSString).lastPathComponent,
			directory: path,
			isWorktree: isWorktree,
			branchName: isWorktree ? "fix_MOB-1" : "master"
		)
	}
}
