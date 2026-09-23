import ComposableArchitecture
import Foundation
import GitCore
import Settings
import TerminalFeature
import Testing
import ToolsIntegration
@testable import RepositoryFeature

// Every built-in terminal a repository opens carries its group's startup command, whichever
// way the tab came to exist: first open, a new tab, or a retry after the shell failed. Groups
// without a command of their own fall back to the global one. The
// trimming and the typing itself are covered in TerminalFeature.
@Suite("Terminal startup command")
@MainActor
struct TerminalStartupCommandTests {
	@Test("first open, new tab and retry all carry the group's command")
	func everyNewSessionCarriesCommand() async {
		let store = makeStore(commands: ["/repos/alpha": "claude"])
		await scanGroups(store)

		await openPanel(store, on: "/repos/alpha")
		#expect(store.state.terminalSessions.map(\.startupCommand) == ["claude"])

		await store.send(.terminalLayout(.newTabRequested))
		#expect(store.state.terminalSessions.map(\.startupCommand) == ["claude", "claude"])

		let first = store.state.terminalSessions[0].id
		await store.send(.terminalLayout(.retryTab(sessionId: first)))
		#expect(store.state.terminalSessions.map(\.startupCommand) == ["claude", "claude"])
		#expect(store.state.terminalSessions[id: first] == nil)
	}

	@Test("a worktree's terminal carries its group's command")
	func worktreeUsesGroupCommand() async {
		let store = makeStore(commands: ["/repos/alpha": "claude"])
		await scanGroups(store)
		await openPanel(store, on: "/repos/alpha")

		await store.send(.terminalLayout(.selectRepo(repositoryPath: "/repos/alpha-fix")))
		#expect(store.state.terminalSessions.map(\.repositoryPath) == ["/repos/alpha", "/repos/alpha-fix"])
		#expect(store.state.terminalSessions.map(\.startupCommand) == ["claude", "claude"])
	}

	@Test("a group's command does not leak into another group's terminals")
	func commandStaysInItsGroup() async {
		let store = makeStore(commands: ["/repos/alpha": "claude", "/repos/beta": "npm start"])
		await scanGroups(store)
		await openPanel(store, on: "/repos/beta")
		await store.send(.terminalLayout(.newTabRequested))
		await store.send(.terminalLayout(.selectRepo(repositoryPath: "/repos/gamma")))
		await store.send(.terminalLayout(.newTabRequested))

		#expect(store.state.terminalSessions.map(\.repositoryPath) == [
			"/repos/beta", "/repos/beta", "/repos/gamma", "/repos/gamma",
		])
		#expect(store.state.terminalSessions.map(\.startupCommand) == ["npm start", "npm start", nil, nil])
	}

	@Test("a repository no group knows starts its terminal idle")
	func unknownRepositoryHasNoCommand() async {
		let store = makeStore(commands: ["/repos/alpha": "claude"])
		await scanGroups(store)
		await openPanel(store, on: "/repos/alpha")

		await store.send(.terminalLayout(.selectRepo(repositoryPath: "/repos/elsewhere")))
		#expect(store.state.terminalSessions.map(\.repositoryPath) == ["/repos/alpha", "/repos/elsewhere"])
		#expect(store.state.terminalSessions.map(\.startupCommand) == ["claude", nil])
	}

	@Test("an edited command applies to the next tab, not to tabs already open")
	func editAppliesToNewTabsOnly() async {
		let store = makeStore(commands: ["/repos/alpha": "claude"])
		await scanGroups(store)

		await openPanel(store, on: "/repos/alpha")
		@Shared(.groupSettings) var groupSettings: [String: RepoGroupSettings] = [:]
		$groupSettings.withLock { $0["/repos/alpha"]?.terminalStartupCommand = "lazygit" }
		await store.send(.terminalLayout(.newTabRequested))

		#expect(store.state.terminalSessions.map(\.startupCommand) == ["claude", "lazygit"])
	}

	@Test("groups without their own command use the global one; a group's own command overrides it")
	func globalCommandIsFallback() async {
		let store = makeStore(commands: ["/repos/alpha": "claude", "/repos/beta": "  "], global: "mise install")
		await scanGroups(store)
		await openPanel(store, on: "/repos/alpha")
		await store.send(.terminalLayout(.selectRepo(repositoryPath: "/repos/beta")))
		await store.send(.terminalLayout(.selectRepo(repositoryPath: "/repos/gamma")))
		await store.send(.terminalLayout(.newTabRequested))
		await store.send(.terminalLayout(.selectRepo(repositoryPath: "/repos/elsewhere")))

		#expect(store.state.terminalSessions.map(\.repositoryPath) == [
			"/repos/alpha", "/repos/beta", "/repos/gamma", "/repos/gamma", "/repos/elsewhere",
		])
		#expect(store.state.terminalSessions.map(\.startupCommand) == [
			"claude", "mise install", "mise install", "mise install", "mise install",
		])
	}

	@Test("a group that opts out of the global command starts idle, unless it has its own command")
	func optOutSkipsGlobalCommand() async {
		let store = makeStore(commands: ["/repos/beta": "npm start"], global: "mise install")
		@Shared(.groupSettings) var groupSettings: [String: RepoGroupSettings] = [:]
		$groupSettings.withLock {
			$0["/repos/alpha"] = RepoGroupSettings(skipGlobalTerminalStartupCommand: true)
			$0["/repos/beta"]?.skipGlobalTerminalStartupCommand = true
		}
		await scanGroups(store)
		await openPanel(store, on: "/repos/alpha")
		await store.send(.terminalLayout(.selectRepo(repositoryPath: "/repos/alpha-fix")))
		await store.send(.terminalLayout(.selectRepo(repositoryPath: "/repos/beta")))
		await store.send(.terminalLayout(.selectRepo(repositoryPath: "/repos/gamma")))

		#expect(store.state.terminalSessions.map(\.repositoryPath) == [
			"/repos/alpha", "/repos/alpha-fix", "/repos/beta", "/repos/gamma",
		])
		#expect(store.state.terminalSessions.map(\.startupCommand) == [nil, nil, "npm start", "mise install"])
	}

	// MARK: - Helpers

	private func makeStore(commands: [String: String], global: String = "") -> TestStoreOf<RepositoryListReducer> {
		@Shared(.groupSettings) var groupSettings: [String: RepoGroupSettings] = [:]
		$groupSettings.withLock {
			$0 = commands.mapValues { RepoGroupSettings(terminalStartupCommand: $0) }
		}
		@Shared(.terminalStartupCommand) var terminalStartupCommand = ""
		$terminalStartupCommand.withLock { $0 = global }

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

	/// alpha (with one worktree), beta, and gamma — gamma has no settings at all.
	private func scanGroups(_ store: TestStoreOf<RepositoryListReducer>) async {
		await store.send(.didScanGroup(rootPath: "/repos/alpha", rows: [
			scanned("/repos/alpha", isWorktree: false),
			scanned("/repos/alpha-fix", isWorktree: true),
		]))
		await store.send(.didScanGroup(rootPath: "/repos/beta", rows: [scanned("/repos/beta", isWorktree: false)]))
		await store.send(.didScanGroup(rootPath: "/repos/gamma", rows: [scanned("/repos/gamma", isWorktree: false)]))
	}

	/// Opens the terminal panel on a group's root, the way the row's terminal button does.
	/// `.selectRepo` and `.newTabRequested` only act inside an open panel.
	private func openPanel(_ store: TestStoreOf<RepositoryListReducer>, on groupId: String) async {
		await store.send(.repositoryGroups(.element(id: groupId, action: .header(.openTerminalForRepo))))
	}

	private func scanned(_ path: String, isWorktree: Bool) -> ScannedRepository {
		ScannedRepository(
			path: path,
			name: (path as NSString).lastPathComponent,
			directory: path,
			isWorktree: isWorktree,
			branchName: isWorktree ? "MOB-1_fix" : "master"
		)
	}
}
