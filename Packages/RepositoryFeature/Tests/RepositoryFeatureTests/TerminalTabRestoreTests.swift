import ComposableArchitecture
import Foundation
import GitCore
import TerminalFeature
import Testing
import ToolsIntegration
@testable import RepositoryFeature

// A relaunch reopens the terminal tabs that were open when the window last closed, each in the
// directory its shell had got to, with the panel on the tab that was on screen.
@Suite("Terminal tabs restored on relaunch")
@MainActor
struct TerminalTabRestoreTests {
	// MARK: - Saving

	@Test("a saved tab records where its shell is, its command, and which tab was showing")
	func savesTabs() {
		let alphaOne = TerminalSession(repositoryPath: "/repos/alpha", startupCommand: "claude", tabIndex: 1)
		let alphaTwo = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 2)
		let beta = TerminalSession(repositoryPath: "/repos/beta", tabIndex: 1)
		var layout = TerminalLayoutReducer.State()
		layout.activate(beta)
		layout.lastActiveSessionByRepo["/repos/alpha"] = alphaTwo.id

		let saved = SavedTerminalTabs(
			sessions: [alphaOne, alphaTwo, beta],
			layout: layout,
			panes: [alphaTwo.id: TerminalPaneSnapshot(directory: "/repos/alpha/Sources")]
		)

		#expect(saved.tabs == [
			// No pane yet, so no shell to ask: it keeps the directory it starts in.
			SavedTerminalTab(
				repositoryPath: "/repos/alpha",
				directory: "/repos/alpha",
				startupCommand: "claude",
				claudeSessionId: nil,
				tabIndex: 1,
				isRepositoryCurrentTab: false,
				isOnScreen: false
			),
			SavedTerminalTab(
				repositoryPath: "/repos/alpha",
				directory: "/repos/alpha/Sources",
				startupCommand: nil,
				claudeSessionId: nil,
				tabIndex: 2,
				isRepositoryCurrentTab: true,
				isOnScreen: false
			),
			SavedTerminalTab(
				repositoryPath: "/repos/beta",
				directory: "/repos/beta",
				startupCommand: nil,
				claudeSessionId: nil,
				tabIndex: 1,
				isRepositoryCurrentTab: true,
				isOnScreen: true
			),
		])
	}

	@Test("a tab whose shell has exited is not saved")
	func failedTabsAreNotSaved() {
		var failed = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		failed.status = .failed("Terminal process exited (code 0)")
		let live = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 2)

		let saved = SavedTerminalTabs(sessions: [failed, live], layout: nil, panes: [:])

		#expect(saved.tabs.map(\.tabIndex) == [2])
	}

	@Test("the save action writes the tabs open now")
	func saveActionWritesTabs() async {
		let alpha = TerminalSession(repositoryPath: "/repos/alpha")
		var initial = RepositoryListReducer.State()
		initial.terminalSessions = [alpha]
		let written = LockIsolated<SavedTerminalTabs?>(nil)
		let store = TestStore(initialState: initial) {
			RepositoryListReducer()
		} withDependencies: {
			$0[TerminalTabArchiveClient.self].save = { written.setValue($0) }
		}

		await store.send(.view(.saveTerminalTabsRequested(panes: [alpha.id: TerminalPaneSnapshot(directory: "/tmp")])))

		#expect(written.value?.tabs.map(\.directory) == ["/tmp"])
	}

	// MARK: - Claude conversations

	private let conversation = "948fa96a-ed30-4a60-ad45-46cd868d3433"

	@Test("a tab with Claude running in it is saved with the conversation, beside its startup command")
	func savesClaudeConversation() {
		let alpha = TerminalSession(repositoryPath: "/repos/alpha", startupCommand: "claude")
		let beta = TerminalSession(repositoryPath: "/repos/beta")

		let saved = SavedTerminalTabs(
			sessions: [alpha, beta],
			layout: nil,
			panes: [
				alpha.id: TerminalPaneSnapshot(directory: "/repos/alpha", claudeSessionId: conversation),
				beta.id: TerminalPaneSnapshot(directory: "/repos/beta"),
			]
		)

		#expect(saved.tabs.map(\.claudeSessionId) == [conversation, nil])
		#expect(saved.tabs.map(\.startupCommand) == ["claude", nil])
	}

	@Test("a restored tab resumes its conversation instead of starting a fresh Claude")
	func restoresClaudeConversation() async {
		let store = makeStore(loading: SavedTerminalTabs(tabs: [
			tab("/repos/alpha", directory: "/repos/alpha", command: "claude", claudeSessionId: conversation),
			tab("/repos/beta", directory: "/repos/beta", claudeSessionId: conversation),
			tab("/repos/gamma", directory: "/repos/gamma", command: "claude"),
		]))

		await store.send(.restoreTerminalTabs)

		let sessions = store.state.terminalSessions
		#expect(sessions.map(\.commandToType) == [
			"claude --resume \(conversation)",
			// Claude typed by hand, in a tab that runs no startup command, is resumed too.
			"claude --resume \(conversation)",
			"claude",
		])
		// What the tab runs by configuration is kept for a retry or the next relaunch.
		#expect(sessions.map(\.startupCommand) == ["claude", nil, "claude"])
		#expect(sessions.map(\.awaitsStartupPrompt) == [true, true, true])
	}

	@Test("Claude exited before the quit: the tab reopens with its startup command, not the old conversation")
	func exitedClaudeIsNotResumedAgain() {
		let resumed = TerminalSession(
			repositoryPath: "/repos/alpha",
			startupCommand: "claude",
			resumingClaudeSession: conversation
		)

		let saved = SavedTerminalTabs(
			sessions: [resumed],
			layout: nil,
			panes: [resumed.id: TerminalPaneSnapshot(directory: "/repos/alpha")]
		)

		#expect(saved.tabs.map(\.claudeSessionId) == [nil])
		#expect(saved.tabs.map(\.startupCommand) == ["claude"])
	}

	@Test("a restored tab whose panel was never opened keeps the conversation it was going to resume")
	func unopenedTabKeepsConversation() {
		let restored = TerminalSession(repositoryPath: "/repos/alpha", resumingClaudeSession: conversation)

		let saved = SavedTerminalTabs(sessions: [restored], layout: nil, panes: [:])

		#expect(saved.tabs.map(\.claudeSessionId) == [conversation])
	}

	@Test("a file saved before conversations were recorded still loads")
	func decodesWithoutConversation() throws {
		let json = """
		{"tabs":[{"repositoryPath":"/repos/alpha","directory":"/repos/alpha","tabIndex":1,\
		"isRepositoryCurrentTab":false,"isOnScreen":true}]}
		"""

		let saved = try JSONDecoder().decode(SavedTerminalTabs.self, from: Data(json.utf8))

		#expect(saved.tabs.map(\.claudeSessionId) == [nil])
	}

	// MARK: - Pruning

	@Test("a tab whose repository is gone is dropped; one whose directory is gone reopens at the root")
	func pruning() {
		let saved = SavedTerminalTabs(tabs: [
			tab("/repos/deleted-worktree", directory: "/repos/deleted-worktree"),
			tab("/repos/alpha", directory: "/repos/alpha/removed-folder"),
			tab("/repos/beta", directory: "/repos/beta/Sources"),
		])
		let existing: Set = ["/repos/alpha", "/repos/beta", "/repos/beta/Sources"]

		let pruned = saved.pruned { existing.contains($0) }

		#expect(pruned.tabs.map(\.repositoryPath) == ["/repos/alpha", "/repos/beta"])
		#expect(pruned.tabs.map(\.directory) == ["/repos/alpha", "/repos/beta/Sources"])
	}

	// MARK: - Restoring

	@Test("restoring reopens the tabs in their directories and the panel on the tab that was showing")
	func restoresTabsAndPanel() async throws {
		let store = makeStore(loading: SavedTerminalTabs(tabs: [
			tab("/repos/alpha", directory: "/repos/alpha/Sources", command: "claude", tabIndex: 1),
			tab("/repos/alpha", directory: "/repos/alpha", tabIndex: 3, isRepositoryCurrentTab: true),
			tab("/repos/beta", directory: "/repos/beta", isRepositoryCurrentTab: true, isOnScreen: true),
		]))

		await store.send(.restoreTerminalTabs)

		let sessions = store.state.terminalSessions
		#expect(sessions.map(\.repositoryPath) == ["/repos/alpha", "/repos/alpha", "/repos/beta"])
		#expect(sessions.map(\.startingDirectory) == ["/repos/alpha/Sources", "/repos/alpha", "/repos/beta"])
		#expect(sessions.map(\.tabIndex) == [1, 3, 1])
		#expect(sessions.map(\.startupCommand) == ["claude", nil, nil])
		// The command is Claude booting, as on any first open: no notification for its prompt.
		#expect(sessions.map(\.awaitsStartupPrompt) == [true, false, false])

		let layout = try #require(store.state.terminalLayout)
		#expect(layout.activeRepositoryPath == "/repos/beta")
		#expect(layout.activeSessionId == sessions[2].id)
		#expect(layout.lastActiveSessionByRepo == [
			"/repos/alpha": sessions[1].id,
			"/repos/beta": sessions[2].id,
		])
	}

	@Test("tabs saved with the panel closed come back with the panel still closed")
	func restoresWithPanelClosed() async {
		let store = makeStore(loading: SavedTerminalTabs(tabs: [tab("/repos/alpha", directory: "/repos/alpha")]))

		await store.send(.restoreTerminalTabs)

		#expect(store.state.terminalSessions.count == 1)
		#expect(store.state.terminalLayout == nil)
	}

	@Test("tabs are restored once per launch, however often the window appears")
	func restoresOnce() async {
		let store = makeStore(loading: SavedTerminalTabs(tabs: [tab("/repos/alpha", directory: "/repos/alpha")]))

		await store.send(.restoreTerminalTabs)
		await store.send(.restoreTerminalTabs)

		#expect(store.state.terminalSessions.count == 1)
	}

	@Test("the toolbar picks up the restored repository's buttons once the scan finds its row")
	func toolbarSyncsAfterScan() async {
		let store = makeStore(loading: SavedTerminalTabs(tabs: [
			tab("/repos/alpha", directory: "/repos/alpha", isRepositoryCurrentTab: true, isOnScreen: true),
		]))
		await store.send(.restoreTerminalTabs)
		#expect(store.state.terminalLayout?.gitActionsMenu == nil)

		await store.send(.didScanGroup(rootPath: "/repos/alpha", rows: [
			ScannedRepository(
				path: "/repos/alpha",
				name: "alpha",
				directory: "/repos/alpha",
				isWorktree: false,
				branchName: "master"
			),
		]))

		let row = store.state.repositoryGroups[id: "/repos/alpha"]?.header
		#expect(row != nil)
		#expect(store.state.terminalLayout?.gitActionsMenu == row?.gitActionsMenu)
	}

	// MARK: - Helpers

	private func tab(
		_ repositoryPath: String,
		directory: String,
		command: String? = nil,
		claudeSessionId: String? = nil,
		tabIndex: Int = 1,
		isRepositoryCurrentTab: Bool = false,
		isOnScreen: Bool = false
	) -> SavedTerminalTab {
		SavedTerminalTab(
			repositoryPath: repositoryPath,
			directory: directory,
			startupCommand: command,
			claudeSessionId: claudeSessionId,
			tabIndex: tabIndex,
			isRepositoryCurrentTab: isRepositoryCurrentTab,
			isOnScreen: isOnScreen
		)
	}

	/// Sessions get fresh ids as they are restored, so the suite reads the resulting state rather
	/// than predicting it.
	private func makeStore(loading saved: SavedTerminalTabs) -> TestStoreOf<RepositoryListReducer> {
		let store = TestStore(initialState: RepositoryListReducer.State()) {
			RepositoryListReducer()
		} withDependencies: {
			$0[TerminalTabArchiveClient.self].load = { saved }
			$0.continuousClock = ImmediateClock()
			$0[GitClient.self].getCurrentBranch = { _ in
				GitPorcelainStatus(parsing: "", didSucceed: false)
			}
			$0[GitClient.self].getOriginRemote = { _ in nil }
			$0[XcodeClient.self].findXcodeProject = { _, _, _ in nil }
		}
		store.exhaustivity = .off
		return store
	}
}
