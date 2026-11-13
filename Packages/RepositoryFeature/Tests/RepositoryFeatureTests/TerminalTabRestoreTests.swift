import ComposableArchitecture
import Foundation
import TerminalFeature
import Testing
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
		var terminals = TerminalTabs(sessions: [alphaOne, alphaTwo, beta])
		terminals.show(alphaTwo)
		terminals.show(beta)
		terminals.showPanel()

		let saved = SavedTerminalTabs(
			terminals,
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

		let saved = SavedTerminalTabs(TerminalTabs(sessions: [failed, live]), panes: [:])

		#expect(saved.tabs.map(\.tabIndex) == [2])
	}

	// Hiding the panel keeps its panes and the keyboard, so they are there to save whether the
	// panel is on screen or not; the file says which it was.
	@Test("a hidden panel is saved with its split and the keyboard, marked as hidden")
	func hiddenPanelSavesItsSplit() {
		let alphaOne = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		let alphaTwo = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 2)
		let beta = TerminalSession(repositoryPath: "/repos/beta", tabIndex: 1)
		var terminals = TerminalTabs(sessions: [alphaOne, alphaTwo, beta])
		terminals.show(alphaTwo)
		terminals.split(showing: beta)
		terminals.showPanel()
		#expect(terminals.shownSessionIds == [alphaTwo.id, beta.id])

		let visible = SavedTerminalTabs(terminals, panes: [:])
		#expect(visible.tabs.map(\.isRepositoryCurrentTab) == [false, true, true])
		#expect(visible.tabs.map(\.isOnScreen) == [false, false, true])
		#expect(visible.tabs.map(\.paneIndex) == [0, 0, 1])
		#expect(visible.tabs.map(\.isPaneCurrentTab) == [false, true, true])
		#expect(visible.isPanelVisible == true)

		terminals.hidePanel()
		let hidden = SavedTerminalTabs(terminals, panes: [:])
		#expect(hidden.tabs.map(\.isRepositoryCurrentTab) == [false, true, true])
		#expect(hidden.tabs == visible.tabs)
		#expect(hidden.isPanelVisible == false)
	}

	// Run tabs and failed ones are not saved. The pane showing one comes back on a tab it has
	// that is, and the keyboard stays with it.
	@Test("a pane showing a tab that is not saved comes back on its first saved tab")
	func paneOnUnsavedTabFallsBackToItsSavedTab() {
		let alpha = TerminalSession(repositoryPath: "/repos/alpha")
		let betaOne = TerminalSession(repositoryPath: "/repos/beta", tabIndex: 1)
		let betaRun = TerminalSession(repositoryPath: "/repos/beta", runTitle: "App", tabIndex: 2)
		var terminals = TerminalTabs(sessions: [alpha, betaOne, betaRun])
		terminals.show(alpha)
		terminals.split(showing: betaRun)
		terminals.showPanel()
		#expect(terminals.activeSessionId == betaRun.id)

		let saved = SavedTerminalTabs(terminals, panes: [:])

		#expect(saved.tabs.map(\.repositoryPath) == ["/repos/alpha", "/repos/beta"])
		#expect(saved.tabs.map(\.isOnScreen) == [false, true])
		#expect(saved.tabs.map(\.paneIndex) == [0, 1])
		#expect(saved.tabs.map(\.isPaneCurrentTab) == [true, true])
	}

	@Test("the keyboard goes to another pane when its own has no tab that is saved")
	func keyboardLeavesPaneWithNoSavedTab() {
		let alpha = TerminalSession(repositoryPath: "/repos/alpha")
		var betaFailed = TerminalSession(repositoryPath: "/repos/beta")
		betaFailed.status = .failed("Terminal process exited (code 1)")
		var terminals = TerminalTabs(sessions: [alpha, betaFailed])
		terminals.show(alpha)
		terminals.split(showing: betaFailed)
		terminals.showPanel()
		#expect(terminals.activeSessionId == betaFailed.id)

		let saved = SavedTerminalTabs(terminals, panes: [:])

		// One pane is left, which is no split: it comes back as the one terminal on screen.
		#expect(saved.tabs.map(\.repositoryPath) == ["/repos/alpha"])
		#expect(saved.tabs.map(\.isOnScreen) == [true])
		#expect(saved.tabs.map(\.paneIndex) == [nil])
		#expect(saved.isPanelVisible == true)
	}

	@Test("a lone pane on a run tab is saved on the repository's other tab, and nothing when it has none")
	func lonePaneOnRunTab() {
		let shell = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		let run = TerminalSession(repositoryPath: "/repos/alpha", runTitle: "App", tabIndex: 2)
		var terminals = TerminalTabs(sessions: [shell, run])
		terminals.show(run)
		terminals.showPanel()

		#expect(SavedTerminalTabs(terminals, panes: [:]).tabs.map(\.isOnScreen) == [true])

		terminals.close([shell.id])
		#expect(SavedTerminalTabs(terminals, panes: [:]).tabs.isEmpty)
	}

	@Test("a single pane is saved as the tab on screen, with no split")
	func singlePaneSavesNoSplit() {
		let alphaOne = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		let alphaTwo = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 2)
		var terminals = TerminalTabs(sessions: [alphaOne, alphaTwo])
		terminals.show(alphaTwo)
		terminals.showPanel()

		let saved = SavedTerminalTabs(terminals, panes: [:])

		#expect(saved.tabs.map(\.isOnScreen) == [false, true])
		#expect(saved.tabs.map(\.paneIndex) == [nil, nil])
		#expect(saved.tabs.map(\.isPaneCurrentTab) == [nil, nil])
	}

	@Test("the save action writes the tabs open now")
	func saveActionWritesTabs() async {
		let alpha = TerminalSession(repositoryPath: "/repos/alpha")
		var initial = RepositoryListReducer.State()
		initial.terminals = TerminalTabs(sessions: [alpha])
		let written = LockIsolated<SavedTerminalTabs?>(nil)
		let store = TestStore(initialState: initial) {
			RepositoryListReducer()
		} withDependencies: {
			$0.uuid = .incrementing
			$0[TerminalTabArchiveClient.self].save = { written.setValue($0) }
			// Where each shell is comes from the panes, read as the tabs are written.
			$0[TerminalPanesClient.self].snapshots = { [alpha.id: TerminalPaneSnapshot(directory: "/tmp")] }
		}

		await store.send(.view(.saveTerminalTabsRequested))

		#expect(written.value?.tabs.map(\.directory) == ["/tmp"])
	}

	// MARK: - The window closing

	@Test("closing the window saves the tabs, hangs every shell up, and the next window restores them")
	func windowClosingSavesKillsAndAllowsRestore() async {
		let log = LockIsolated<[String]>([])
		let written = LockIsolated<SavedTerminalTabs?>(nil)
		let killed = LockIsolated<[[UUID]]>([])
		let store = TestStore(initialState: RepositoryListReducer.State()) {
			RepositoryListReducer()
		} withDependencies: {
			$0.uuid = .incrementing
			$0[TerminalTabArchiveClient.self].load = {
				written.value ?? SavedTerminalTabs(tabs: [
					self.tab("/repos/alpha", directory: "/repos/alpha", command: "claude", isRepositoryCurrentTab: true),
					self.tab("/repos/beta", directory: "/repos/beta", isRepositoryCurrentTab: true, isOnScreen: true),
				])
			}
			$0[TerminalTabArchiveClient.self].save = { tabs in
				log.withValue { $0.append("save") }
				written.setValue(tabs)
			}
			$0[TerminalPanesClient.self].snapshots = {
				log.withValue { $0.append("snapshots") }
				// The second session restored is beta's.
				return [UUID(1): TerminalPaneSnapshot(directory: "/repos/beta/Sources")]
			}
			$0[TerminalPanesClient.self].killAll = { log.withValue { $0.append("killAll") } }
			$0[TerminalPanesClient.self].kill = { ids in killed.withValue { $0.append(ids) } }
		}
		// `hasRestoredTerminalTabs` is private to the reducer, so the state cannot be spelled out.
		store.exhaustivity = .off

		await store.send(.restoreTerminalTabs)
		let opened = store.state.terminals
		#expect(opened.sessions.map(\.id) == [UUID(0), UUID(1)])
		#expect(opened.isPanelVisible)
		#expect(store.state.terminalLayout != nil)

		await store.send(.view(.onDisappear))
		// The panes are read and the tabs written before the shells go, all before returning.
		#expect(log.value == ["snapshots", "save", "killAll"])
		#expect(written.value == SavedTerminalTabs(tabs: [
			tab("/repos/alpha", directory: "/repos/alpha", command: "claude", isRepositoryCurrentTab: true),
			tab("/repos/beta", directory: "/repos/beta/Sources", isRepositoryCurrentTab: true, isOnScreen: true),
		], isPanelVisible: true))
		#expect(store.state.terminals == TerminalTabs())
		#expect(store.state.terminalLayout == nil)
		await store.finish()
		// The sessions left the state, so their panes are dropped as for any closed tab.
		#expect(killed.value.map(Set.init) == [[UUID(0), UUID(1)]])

		// The next window's `onAppear` sends this again, and it is no longer a no-op.
		await store.send(.restoreTerminalTabs)
		let reopened = store.state.terminals
		#expect(reopened.sessions.map(\.id) == [UUID(2), UUID(3)])
		#expect(reopened.sessions.map(\.startingDirectory) == ["/repos/alpha", "/repos/beta/Sources"])
		#expect(reopened.activeSessionId == UUID(3))
		#expect(reopened.isPanelVisible)
		#expect(store.state.terminalLayout != nil)
	}

	@Test("a window closed with the panel hidden reopens with it hidden, its split behind it")
	func windowClosingWithHiddenSplit() async {
		let alphaOne = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		let alphaTwo = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 2)
		let beta = TerminalSession(repositoryPath: "/repos/beta")
		var terminals = TerminalTabs(sessions: [alphaOne, alphaTwo, beta])
		terminals.show(alphaTwo)
		terminals.split(showing: beta)
		var initial = RepositoryListReducer.State()
		initial.terminals = terminals
		let written = LockIsolated<SavedTerminalTabs?>(nil)
		let store = TestStore(initialState: initial) {
			RepositoryListReducer()
		} withDependencies: {
			$0.uuid = .incrementing
			$0[TerminalTabArchiveClient.self].load = { written.value }
			$0[TerminalTabArchiveClient.self].save = { written.setValue($0) }
			// No pane was ever created: the panel has not been on screen.
			$0[TerminalPanesClient.self].snapshots = { [:] }
			$0[TerminalPanesClient.self].killAll = {}
			$0[TerminalPanesClient.self].kill = { _ in }
		}
		store.exhaustivity = .off

		await store.send(.view(.onDisappear))
		#expect(written.value == SavedTerminalTabs(tabs: [
			tab("/repos/alpha", directory: "/repos/alpha", tabIndex: 1, paneIndex: 0, isPaneCurrentTab: false),
			tab(
				"/repos/alpha",
				directory: "/repos/alpha",
				tabIndex: 2,
				isRepositoryCurrentTab: true,
				paneIndex: 0,
				isPaneCurrentTab: true
			),
			tab(
				"/repos/beta",
				directory: "/repos/beta",
				isRepositoryCurrentTab: true,
				isOnScreen: true,
				paneIndex: 1,
				isPaneCurrentTab: true
			),
		], isPanelVisible: false))
		await store.finish()

		await store.send(.restoreTerminalTabs)
		let restored = store.state.terminals
		#expect(restored.sessions.count == 3)
		// The split is where hiding left it, for the panel to show when it is next opened.
		let ids = restored.sessions.map(\.id)
		#expect(restored.panes == [
			TerminalPane(shown: ids[1], tabs: [ids[0], ids[1]]),
			TerminalPane(shown: ids[2], tabs: [ids[2]]),
		])
		#expect(restored.activePaneIndex == 1)
		#expect(!restored.isPanelVisible)
		#expect(store.state.terminalLayout == nil)
		#expect(restored.lastActiveSessionByRepo == [
			"/repos/alpha": restored.sessions[1].id,
			"/repos/beta": restored.sessions[2].id,
		])
	}

	// MARK: - Claude conversations

	private let conversation = "948fa96a-ed30-4a60-ad45-46cd868d3433"

	@Test("a tab with Claude running in it is saved with the conversation, beside its startup command")
	func savesClaudeConversation() {
		let alpha = TerminalSession(repositoryPath: "/repos/alpha", startupCommand: "claude")
		let beta = TerminalSession(repositoryPath: "/repos/beta")

		let saved = SavedTerminalTabs(
			TerminalTabs(sessions: [alpha, beta]),
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

		let sessions = store.state.terminals.sessions
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
			TerminalTabs(sessions: [resumed]),
			panes: [resumed.id: TerminalPaneSnapshot(directory: "/repos/alpha")]
		)

		#expect(saved.tabs.map(\.claudeSessionId) == [nil])
		#expect(saved.tabs.map(\.startupCommand) == ["claude"])
	}

	@Test("a restored tab whose panel was never opened keeps the conversation it was going to resume")
	func unopenedTabKeepsConversation() {
		let restored = TerminalSession(repositoryPath: "/repos/alpha", resumingClaudeSession: conversation)

		let saved = SavedTerminalTabs(TerminalTabs(sessions: [restored]), panes: [:])

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
		], isPanelVisible: false)
		let existing: Set = ["/repos/alpha", "/repos/beta", "/repos/beta/Sources"]

		let pruned = saved.pruned { existing.contains($0) }

		#expect(pruned.tabs.map(\.repositoryPath) == ["/repos/alpha", "/repos/beta"])
		#expect(pruned.tabs.map(\.directory) == ["/repos/alpha", "/repos/beta/Sources"])
		// What the file says of the panel is not the tabs' to lose: dropped here, a panel hidden
		// at quit came back on screen.
		#expect(pruned.isPanelVisible == false)
	}

	// MARK: - Restoring

	@Test("restoring reopens the tabs in their directories and the panel on the tab that was showing")
	func restoresTabsAndPanel() async {
		let store = makeStore(loading: SavedTerminalTabs(tabs: [
			tab("/repos/alpha", directory: "/repos/alpha/Sources", command: "claude", tabIndex: 1),
			tab("/repos/alpha", directory: "/repos/alpha", tabIndex: 3, isRepositoryCurrentTab: true),
			tab("/repos/beta", directory: "/repos/beta", isRepositoryCurrentTab: true, isOnScreen: true),
		]))

		await store.send(.restoreTerminalTabs)

		let sessions = store.state.terminals.sessions
		#expect(sessions.map(\.repositoryPath) == ["/repos/alpha", "/repos/alpha", "/repos/beta"])
		#expect(sessions.map(\.startingDirectory) == ["/repos/alpha/Sources", "/repos/alpha", "/repos/beta"])
		#expect(sessions.map(\.tabIndex) == [1, 3, 1])
		#expect(sessions.map(\.startupCommand) == ["claude", nil, nil])
		// The command is Claude booting, as on any first open: no notification for its prompt.
		#expect(sessions.map(\.awaitsStartupPrompt) == [true, false, false])

		let terminals = store.state.terminals
		#expect(terminals.isPanelVisible)
		#expect(store.state.terminalLayout != nil)
		#expect(terminals.activeRepositoryPath == "/repos/beta")
		#expect(terminals.activeSessionId == sessions[2].id)
		#expect(terminals.panes == [TerminalPane(shown: sessions[2].id, tabs: [sessions[2].id])])
		#expect(terminals.lastActiveSessionByRepo == [
			"/repos/alpha": sessions[1].id,
			"/repos/beta": sessions[2].id,
		])
	}

	@Test("the pane that comes back has every tab of its repository, on the one that was on screen")
	func restoredPaneHasItsRepositorysTabs() async {
		let store = makeStore(loading: SavedTerminalTabs(tabs: [
			tab("/repos/alpha", directory: "/repos/alpha", tabIndex: 1, isRepositoryCurrentTab: true, isOnScreen: true),
			tab("/repos/beta", directory: "/repos/beta", isRepositoryCurrentTab: true),
			tab("/repos/alpha", directory: "/repos/alpha", tabIndex: 2),
		]))

		await store.send(.restoreTerminalTabs)

		let ids = store.state.terminals.sessions.map(\.id)
		#expect(store.state.terminals.panes == [TerminalPane(shown: ids[0], tabs: [ids[0], ids[2]])])
		#expect(store.state.terminals.recentSessionIds == [ids[0]])
	}

	@Test("a split of which one pane is left comes back as that one terminal")
	func splitWithOnePaneLeftRestoresOnePane() async {
		// The other pane showed a tab that was not saved (a run tab, a failed one).
		let store = makeStore(loading: SavedTerminalTabs(tabs: [
			tab("/repos/alpha", directory: "/repos/alpha", tabIndex: 1, paneIndex: 1, isPaneCurrentTab: false),
			tab(
				"/repos/alpha",
				directory: "/repos/alpha",
				tabIndex: 2,
				isRepositoryCurrentTab: true,
				isOnScreen: true,
				paneIndex: 1,
				isPaneCurrentTab: true
			),
		]))

		await store.send(.restoreTerminalTabs)

		let ids = store.state.terminals.sessions.map(\.id)
		#expect(store.state.terminals.panes == [TerminalPane(shown: ids[1], tabs: [ids[0], ids[1]])])
		#expect(store.state.terminals.activePaneIndex == 0)
		#expect(store.state.terminals.isPanelVisible)
	}

	// The whole way round, as a quit with a run tab at the keyboard goes: the panel used to come
	// back closed, its split gone, because the tab that had the keyboard was not in the file.
	@Test("a split quit with the keyboard on a run tab comes back, on that pane's shell tab")
	func splitWithKeyboardOnRunTabComesBack() async {
		let alpha = TerminalSession(repositoryPath: "/repos/alpha")
		let betaShell = TerminalSession(repositoryPath: "/repos/beta", tabIndex: 1)
		let betaRun = TerminalSession(repositoryPath: "/repos/beta", runTitle: "App", tabIndex: 2)
		var terminals = TerminalTabs(sessions: [alpha, betaShell, betaRun])
		terminals.show(alpha)
		terminals.split(showing: betaRun)
		terminals.showPanel()
		let store = makeStore(loading: SavedTerminalTabs(terminals, panes: [:]))

		await store.send(.restoreTerminalTabs)

		let ids = store.state.terminals.sessions.map(\.id)
		#expect(store.state.terminals.sessions.map(\.repositoryPath) == ["/repos/alpha", "/repos/beta"])
		#expect(store.state.terminals.panes == [
			TerminalPane(shown: ids[0], tabs: [ids[0]]),
			TerminalPane(shown: ids[1], tabs: [ids[1]]),
		])
		#expect(store.state.terminals.activePaneIndex == 1)
		#expect(store.state.terminals.isPanelVisible)
	}

	@Test("a split whose tab with the keyboard is gone comes back with the keyboard in its first pane")
	func splitWithoutItsKeyboardTabComesBack() async {
		// Three panes were saved; the first, which had the keyboard, was a worktree deleted since.
		// Pruned as the live load prunes it, which leaves panes 1 and 2 and no pane 0.
		let saved = SavedTerminalTabs(tabs: [
			tab(
				"/repos/gone",
				directory: "/repos/gone",
				isRepositoryCurrentTab: true,
				isOnScreen: true,
				paneIndex: 0,
				isPaneCurrentTab: true
			),
			tab("/repos/alpha", directory: "/repos/alpha", isRepositoryCurrentTab: true, paneIndex: 1, isPaneCurrentTab: true),
			tab("/repos/beta", directory: "/repos/beta", isRepositoryCurrentTab: true, paneIndex: 2, isPaneCurrentTab: true),
		], isPanelVisible: true)
		let store = makeStore(loading: saved.pruned { $0 != "/repos/gone" })

		await store.send(.restoreTerminalTabs)

		let ids = store.state.terminals.sessions.map(\.id)
		#expect(store.state.terminals.sessions.map(\.repositoryPath) == ["/repos/alpha", "/repos/beta"])
		#expect(store.state.terminals.panes == [
			TerminalPane(shown: ids[0], tabs: [ids[0]]),
			TerminalPane(shown: ids[1], tabs: [ids[1]]),
		])
		#expect(store.state.terminals.activePaneIndex == 0)
		#expect(store.state.terminals.isPanelVisible)
	}

	@Test("a file from before hidden panels kept their panes opens the panel on the tab on screen")
	func fileWithoutPanelVisibilityShowsThePanel() async {
		let store = makeStore(loading: SavedTerminalTabs(tabs: [
			tab("/repos/alpha", directory: "/repos/alpha", isRepositoryCurrentTab: true, isOnScreen: true),
		]))

		await store.send(.restoreTerminalTabs)

		#expect(store.state.terminals.isPanelVisible)
	}

	@Test("tabs saved with the panel closed come back with the panel still closed")
	func restoresWithPanelClosed() async {
		let store = makeStore(loading: SavedTerminalTabs(tabs: [tab("/repos/alpha", directory: "/repos/alpha")]))

		await store.send(.restoreTerminalTabs)

		#expect(store.state.terminals.sessions.count == 1)
		#expect(store.state.terminals.panes.isEmpty)
		#expect(!store.state.terminals.isPanelVisible)
		#expect(store.state.terminalLayout == nil)
	}

	@Test("with the panel closed each repository still comes back on the tab it was showing")
	func closedPanelRemembersCurrentTabs() async {
		let store = makeStore(loading: SavedTerminalTabs(tabs: [
			tab("/repos/alpha", directory: "/repos/alpha", tabIndex: 1),
			tab("/repos/alpha", directory: "/repos/alpha", tabIndex: 2, isRepositoryCurrentTab: true),
		]))

		await store.send(.restoreTerminalTabs)
		let ids = store.state.terminals.sessions.map(\.id)
		#expect(store.state.terminals.lastActiveSessionByRepo == ["/repos/alpha": ids[1]])
		#expect(store.state.terminalLayout == nil)

		await store.send(.terminals(.selectRepo(repositoryPath: "/repos/alpha")))
		#expect(store.state.terminals.panes == [TerminalPane(shown: ids[1], tabs: ids)])
		#expect(store.state.terminals.isPanelVisible)
		#expect(store.state.terminalLayout != nil)
	}

	@Test("tabs are restored once per launch, however often the window appears")
	func restoresOnce() async {
		let store = makeStore(loading: SavedTerminalTabs(tabs: [tab("/repos/alpha", directory: "/repos/alpha")]))

		await store.send(.restoreTerminalTabs)
		await store.send(.restoreTerminalTabs)

		#expect(store.state.terminals.sessions.count == 1)
	}

	// MARK: - Helpers

	private func tab(
		_ repositoryPath: String,
		directory: String,
		command: String? = nil,
		claudeSessionId: String? = nil,
		tabIndex: Int = 1,
		isRepositoryCurrentTab: Bool = false,
		isOnScreen: Bool = false,
		paneIndex: Int? = nil,
		isPaneCurrentTab: Bool? = nil
	) -> SavedTerminalTab {
		SavedTerminalTab(
			repositoryPath: repositoryPath,
			directory: directory,
			startupCommand: command,
			claudeSessionId: claudeSessionId,
			tabIndex: tabIndex,
			isRepositoryCurrentTab: isRepositoryCurrentTab,
			isOnScreen: isOnScreen,
			paneIndex: paneIndex,
			isPaneCurrentTab: isPaneCurrentTab
		)
	}

	/// Sessions get fresh ids as they are restored, so the suite reads the resulting state rather
	/// than predicting it.
	private func makeStore(loading saved: SavedTerminalTabs) -> TestStoreOf<RepositoryListReducer> {
		let store = TestStore(initialState: RepositoryListReducer.State()) {
			RepositoryListReducer()
		} withDependencies: {
			$0.uuid = .incrementing
			$0[TerminalTabArchiveClient.self].load = { saved }
		}
		store.exhaustivity = .off
		return store
	}
}
