import ComposableArchitecture
import Foundation
import TerminalFeature
import Testing
@testable import RepositoryFeature

// The tabs-and-panes reducer on its own, without the repository list around it: what it does to
// `TerminalTabs` itself, what it asks its parent to build, and what it asks of the panes.
@Suite("Terminal workspace reducer")
@MainActor
struct TerminalWorkspaceReducerTests {
	private typealias Delegate = TerminalWorkspaceReducer.Action.Delegate

	private static let alpha = "/repos/alpha"
	private static let beta = "/repos/beta"

	private func session(_ path: String, _ tabIndex: Int = 1) -> TerminalSession {
		TerminalSession(repositoryPath: path, tabIndex: tabIndex)
	}

	/// One pane showing `shown`, with `tabs` in its bar (just `shown` by default).
	private func pane(_ shown: TerminalSession, _ tabs: [TerminalSession]? = nil) -> TerminalPane {
		TerminalPane(shown: shown.id, tabs: (tabs ?? [shown]).map(\.id))
	}

	private func makeStore(
		_ state: TerminalTabs,
		dependencies: (inout DependencyValues) -> Void = { _ in }
	) -> TestStoreOf<TerminalWorkspaceReducer> {
		TestStore(initialState: state) {
			TerminalWorkspaceReducer()
		} withDependencies: {
			dependencies(&$0)
		}
	}

	// MARK: - Tabs and panes

	@Test("selecting a tab shows it in its pane and gives it the keyboard")
	func selectTabShowsIt() async {
		let one = session(Self.alpha, 1)
		let two = session(Self.alpha, 2)
		let store = makeStore(TerminalTabs(
			sessions: [one, two],
			panes: [pane(one, [one, two])],
			isPanelVisible: true,
			lastActiveSessionByRepo: [Self.alpha: one.id],
			recentSessionIds: [one.id]
		))

		await store.send(.selectTab(sessionId: two.id)) {
			$0 = TerminalTabs(
				sessions: [one, two],
				panes: [self.pane(two, [one, two])],
				isPanelVisible: true,
				lastActiveSessionByRepo: [Self.alpha: two.id],
				recentSessionIds: [one.id, two.id]
			)
		}
		// An id that names no tab is ignored.
		await store.send(.selectTab(sessionId: UUID()))
	}

	@Test("a clicked pane takes the keyboard")
	func paneFocusedMovesKeyboard() async {
		let alpha = session(Self.alpha)
		let beta = session(Self.beta)
		let store = makeStore(TerminalTabs(
			sessions: [alpha, beta],
			panes: [pane(alpha), pane(beta)],
			isPanelVisible: true,
			lastActiveSessionByRepo: [Self.alpha: alpha.id],
			recentSessionIds: [alpha.id]
		))

		await store.send(.paneFocused(sessionId: beta.id)) {
			$0 = TerminalTabs(
				sessions: [alpha, beta],
				panes: [self.pane(alpha), self.pane(beta)],
				activePaneIndex: 1,
				isPanelVisible: true,
				lastActiveSessionByRepo: [Self.alpha: alpha.id, Self.beta: beta.id],
				recentSessionIds: [alpha.id, beta.id]
			)
		}
	}

	@Test("cycling panes moves the keyboard to the next pane and wraps around")
	func cyclePaneMovesKeyboard() async {
		let alpha = session(Self.alpha)
		let beta = session(Self.beta)
		let store = makeStore(TerminalTabs(
			sessions: [alpha, beta],
			panes: [pane(alpha), pane(beta)],
			isPanelVisible: true,
			lastActiveSessionByRepo: [Self.alpha: alpha.id],
			recentSessionIds: [alpha.id]
		))

		await store.send(.cyclePaneRequested(forward: true)) {
			$0 = TerminalTabs(
				sessions: [alpha, beta],
				panes: [self.pane(alpha), self.pane(beta)],
				activePaneIndex: 1,
				isPanelVisible: true,
				lastActiveSessionByRepo: [Self.alpha: alpha.id, Self.beta: beta.id],
				recentSessionIds: [alpha.id, beta.id]
			)
		}
		// Past the last pane is the first again; backward from there is the last.
		await store.send(.cyclePaneRequested(forward: true)) {
			$0 = TerminalTabs(
				sessions: [alpha, beta],
				panes: [self.pane(alpha), self.pane(beta)],
				isPanelVisible: true,
				lastActiveSessionByRepo: [Self.alpha: alpha.id, Self.beta: beta.id],
				recentSessionIds: [beta.id, alpha.id]
			)
		}
		await store.send(.cyclePaneRequested(forward: false)) {
			$0 = TerminalTabs(
				sessions: [alpha, beta],
				panes: [self.pane(alpha), self.pane(beta)],
				activePaneIndex: 1,
				isPanelVisible: true,
				lastActiveSessionByRepo: [Self.alpha: alpha.id, Self.beta: beta.id],
				recentSessionIds: [alpha.id, beta.id]
			)
		}
	}

	@Test("cycling panes does nothing with one pane on screen")
	func cyclePaneNeedsSplit() async {
		let one = session(Self.alpha, 1)
		let two = session(Self.alpha, 2)
		let store = makeStore(TerminalTabs(
			sessions: [one, two],
			panes: [pane(one, [one, two])],
			isPanelVisible: true
		))

		await store.send(.cyclePaneRequested(forward: true))
		await store.send(.cyclePaneRequested(forward: false))
	}

	@Test("closing a pane takes it out of the split and keeps its tab open")
	func closePaneKeepsTab() async {
		let alpha = session(Self.alpha)
		let beta = session(Self.beta)
		let store = makeStore(TerminalTabs(
			sessions: [alpha, beta],
			panes: [pane(alpha), pane(beta)],
			isPanelVisible: true,
			lastActiveSessionByRepo: [Self.alpha: alpha.id],
			recentSessionIds: [alpha.id]
		))

		await store.send(.closePane(sessionId: alpha.id)) {
			$0 = TerminalTabs(
				sessions: [alpha, beta],
				panes: [self.pane(beta)],
				isPanelVisible: true,
				lastActiveSessionByRepo: [Self.alpha: alpha.id, Self.beta: beta.id],
				recentSessionIds: [alpha.id, beta.id]
			)
		}
	}

	// The shells are hung up by the repository list once the sessions have left the state, so on
	// its own this reducer needs no panes client to close a tab: the unimplemented test value
	// would fail these tests if it were called.
	@Test("killing a tab closes it and moves its pane on to the next one")
	func killTabClosesIt() async {
		let one = session(Self.alpha, 1)
		let two = session(Self.alpha, 2)
		let store = makeStore(TerminalTabs(
			sessions: [one, two],
			panes: [pane(one, [one, two])],
			isPanelVisible: true,
			lastActiveSessionByRepo: [Self.alpha: one.id],
			recentSessionIds: [one.id]
		))

		await store.send(.killTab(sessionId: one.id)) {
			$0 = TerminalTabs(
				sessions: [two],
				panes: [self.pane(two)],
				isPanelVisible: true,
				lastActiveSessionByRepo: [Self.alpha: two.id],
				recentSessionIds: [two.id]
			)
		}
	}

	@Test("killing a repository closes all of its tabs; the last one closing hides the panel")
	func killRepoClosesItsTabs() async {
		let one = session(Self.alpha, 1)
		let two = session(Self.alpha, 2)
		let beta = session(Self.beta)
		let store = makeStore(TerminalTabs(
			sessions: [one, beta, two],
			panes: [pane(one, [one, two])],
			isPanelVisible: true,
			lastActiveSessionByRepo: [Self.alpha: one.id],
			recentSessionIds: [one.id]
		))

		// The panel moves to the repository that is left.
		await store.send(.killRepo(repositoryPath: Self.alpha)) {
			$0 = TerminalTabs(
				sessions: [beta],
				panes: [self.pane(beta)],
				isPanelVisible: true,
				lastActiveSessionByRepo: [Self.beta: beta.id],
				recentSessionIds: [beta.id]
			)
		}
		await store.send(.killRepo(repositoryPath: Self.beta)) {
			$0 = TerminalTabs()
		}
	}

	@Test("hiding the panel keeps the panes and the keyboard where they are")
	func hidePanelKeepsPanes() async {
		let alpha = session(Self.alpha)
		let beta = session(Self.beta)
		let store = makeStore(TerminalTabs(
			sessions: [alpha, beta],
			panes: [pane(alpha), pane(beta)],
			activePaneIndex: 1,
			isPanelVisible: true,
			lastActiveSessionByRepo: [Self.alpha: alpha.id, Self.beta: beta.id],
			recentSessionIds: [alpha.id, beta.id]
		))

		await store.send(.hidePanelRequested) {
			$0 = TerminalTabs(
				sessions: [alpha, beta],
				panes: [self.pane(alpha), self.pane(beta)],
				activePaneIndex: 1,
				isPanelVisible: false,
				lastActiveSessionByRepo: [Self.alpha: alpha.id, Self.beta: beta.id],
				recentSessionIds: [alpha.id, beta.id]
			)
		}
	}

	// MARK: - Selecting a repository

	@Test("selecting a repository with a tab shows the one it was last on, and the panel")
	func selectRepoShowsExistingTab() async {
		let one = session(Self.alpha, 1)
		let two = session(Self.alpha, 2)
		let store = makeStore(TerminalTabs(
			sessions: [one, two],
			lastActiveSessionByRepo: [Self.alpha: two.id]
		))

		await store.send(.selectRepo(repositoryPath: Self.alpha)) {
			$0 = TerminalTabs(
				sessions: [one, two],
				panes: [self.pane(two, [one, two])],
				isPanelVisible: true,
				lastActiveSessionByRepo: [Self.alpha: two.id],
				recentSessionIds: [two.id]
			)
		}
	}

	@Test("selecting a repository without a tab asks for its first one")
	func selectRepoRequestsFirstTab() async {
		let store = makeStore(TerminalTabs())

		await store.send(.selectRepo(repositoryPath: Self.alpha))
		await store.receive(\.delegate, .sessionRequested(.firstTab(repositoryPath: Self.alpha), .tab))
	}

	// MARK: - Asking for a session

	@Test("⌘T asks for another tab of the active repository, at its root")
	func newTabRequestsExtraTab() async {
		let alpha = session(Self.alpha)
		let store = makeStore(TerminalTabs(sessions: [alpha], panes: [pane(alpha)], isPanelVisible: true))

		await store.send(.newTabRequested)
		await store.receive(\.delegate, .sessionRequested(.extraTab(repositoryPath: Self.alpha, directory: nil), .tab))
	}

	@Test("⌘T does nothing while no terminal has the keyboard")
	func newTabNeedsActiveRepository() async {
		let store = makeStore(TerminalTabs(sessions: [session(Self.alpha)]))

		await store.send(.newTabRequested)
	}

	@Test("⌘D asks for a tab in a pane of its own, opened where the active terminal's shell is")
	func splitRequestsTabInActiveDirectory() async {
		let alpha = session(Self.alpha)
		let beta = session(Self.beta)
		let asked = LockIsolated<[UUID]>([])
		let store = makeStore(TerminalTabs(
			sessions: [alpha, beta],
			panes: [pane(alpha), pane(beta)],
			activePaneIndex: 1,
			isPanelVisible: true
		)) {
			$0[TerminalPanesClient.self].currentDirectory = { sessionId in
				asked.withValue { $0.append(sessionId) }
				return "/repos/beta/Sources"
			}
		}

		await store.send(.splitRequested)
		await store.receive(
			\.delegate,
			.sessionRequested(.extraTab(repositoryPath: Self.beta, directory: "/repos/beta/Sources"), .split)
		)
		#expect(asked.value == [beta.id])
	}

	@Test("⌘D does nothing when the panel already shows three panes")
	func splitNeedsRoom() async {
		let sessions = (1 ... 3).map { session(Self.alpha, $0) }
		let store = makeStore(TerminalTabs(
			sessions: IdentifiedArray(uniqueElements: sessions),
			panes: sessions.map { pane($0) },
			isPanelVisible: true
		)) {
			$0[TerminalPanesClient.self].currentDirectory = { _ in
				Issue.record("the directory is not read when there is no room to split")
				return nil
			}
		}

		await store.send(.splitRequested)
	}

	// The directory is read in an effect, so a third pane can open before the session ⌘D asked
	// for is built. It is then left out, sessions included: nothing would show it or hang it up.
	@Test("a session built for a split is dropped when the panel has filled up meanwhile")
	func splitSessionBuiltWithNoRoomIsDropped() async {
		let sessions = (1 ... 3).map { session(Self.alpha, $0) }
		let store = makeStore(TerminalTabs(
			sessions: IdentifiedArray(uniqueElements: sessions),
			panes: sessions.map { pane($0) },
			isPanelVisible: true
		))

		await store.send(.sessionBuilt(session(Self.alpha, 4), .split))
	}

	@Test("a repository with a tab opens in a pane beside the active one")
	func openRepoInSplitShowsExistingTab() async {
		let alpha = session(Self.alpha)
		let betaOne = session(Self.beta, 1)
		let betaTwo = session(Self.beta, 2)
		let store = makeStore(TerminalTabs(
			sessions: [alpha, betaOne, betaTwo],
			panes: [pane(alpha)],
			isPanelVisible: true,
			lastActiveSessionByRepo: [Self.alpha: alpha.id, Self.beta: betaTwo.id],
			recentSessionIds: [alpha.id]
		))

		await store.send(.openRepoInSplit(repositoryPath: Self.beta)) {
			$0 = TerminalTabs(
				sessions: [alpha, betaOne, betaTwo],
				panes: [self.pane(alpha), self.pane(betaTwo, [betaOne, betaTwo])],
				activePaneIndex: 1,
				isPanelVisible: true,
				lastActiveSessionByRepo: [Self.alpha: alpha.id, Self.beta: betaTwo.id],
				recentSessionIds: [alpha.id, betaTwo.id]
			)
		}
	}

	@Test("a repository without a tab asks for its first one, to go in a pane of its own")
	func openRepoInSplitRequestsFirstTab() async {
		let alpha = session(Self.alpha)
		let store = makeStore(TerminalTabs(sessions: [alpha], panes: [pane(alpha)], isPanelVisible: true))

		await store.send(.openRepoInSplit(repositoryPath: Self.beta))
		await store.receive(\.delegate, .sessionRequested(.firstTab(repositoryPath: Self.beta), .split))
	}

	@Test("retrying a tab asks for a session to take its place")
	func retryRequestsReplacement() async {
		let alpha = session(Self.alpha)
		let store = makeStore(TerminalTabs(sessions: [alpha], panes: [pane(alpha)], isPanelVisible: true))

		await store.send(.retryTab(sessionId: alpha.id))
		await store.receive(\.delegate, .sessionRequested(.replacement(of: alpha), .replacing(alpha.id)))
		// A tab that has closed since is not retried.
		await store.send(.retryTab(sessionId: UUID()))
	}

	// MARK: - Placing a built session

	@Test("a session built as a tab joins the active pane, is shown, and brings the panel up")
	func sessionBuiltAsTab() async {
		let one = session(Self.alpha, 1)
		let two = session(Self.alpha, 2)
		// The panel was hidden with the pane in place.
		let store = makeStore(TerminalTabs(
			sessions: [one],
			panes: [pane(one)],
			lastActiveSessionByRepo: [Self.alpha: one.id],
			recentSessionIds: [one.id]
		))

		await store.send(.sessionBuilt(two, .tab)) {
			$0 = TerminalTabs(
				sessions: [one, two],
				panes: [self.pane(two, [one, two])],
				isPanelVisible: true,
				lastActiveSessionByRepo: [Self.alpha: two.id],
				recentSessionIds: [one.id, two.id]
			)
		}
	}

	@Test("the first session built opens the panel on it")
	func sessionBuiltAsFirstTab() async {
		let alpha = session(Self.alpha)
		let store = makeStore(TerminalTabs())

		await store.send(.sessionBuilt(alpha, .tab)) {
			$0 = TerminalTabs(
				sessions: [alpha],
				panes: [self.pane(alpha)],
				isPanelVisible: true,
				lastActiveSessionByRepo: [Self.alpha: alpha.id],
				recentSessionIds: [alpha.id]
			)
		}
	}

	@Test("a session built for a split gets a pane of its own right of the active one")
	func sessionBuiltAsSplit() async {
		let one = session(Self.alpha, 1)
		let two = session(Self.alpha, 2)
		let store = makeStore(TerminalTabs(
			sessions: [one],
			panes: [pane(one)],
			isPanelVisible: true,
			lastActiveSessionByRepo: [Self.alpha: one.id],
			recentSessionIds: [one.id]
		))

		await store.send(.sessionBuilt(two, .split)) {
			$0 = TerminalTabs(
				sessions: [one, two],
				panes: [self.pane(one), self.pane(two)],
				activePaneIndex: 1,
				isPanelVisible: true,
				lastActiveSessionByRepo: [Self.alpha: two.id],
				recentSessionIds: [one.id, two.id]
			)
		}
	}

	@Test("a replacement takes the old session's place in the bar and in its pane")
	func sessionBuiltAsReplacement() async {
		let one = session(Self.alpha, 1)
		let two = session(Self.alpha, 2)
		let retried = session(Self.alpha, 1)
		let store = makeStore(TerminalTabs(
			sessions: [one, two],
			panes: [pane(one, [one, two])],
			isPanelVisible: true,
			lastActiveSessionByRepo: [Self.alpha: one.id],
			recentSessionIds: [two.id, one.id]
		))

		await store.send(.sessionBuilt(retried, .replacing(one.id))) {
			$0 = TerminalTabs(
				sessions: [retried, two],
				panes: [self.pane(retried, [retried, two])],
				isPanelVisible: true,
				lastActiveSessionByRepo: [Self.alpha: retried.id],
				recentSessionIds: [two.id, retried.id]
			)
		}
	}

	// MARK: - ⌘W

	@Test("⌘W closes the active tab while its repository has another")
	func closeActiveTabWithSiblingTab() async {
		let one = session(Self.alpha, 1)
		let two = session(Self.alpha, 2)
		let store = makeStore(TerminalTabs(
			sessions: [one, two],
			panes: [pane(two, [one, two])],
			isPanelVisible: true,
			lastActiveSessionByRepo: [Self.alpha: two.id],
			recentSessionIds: [two.id]
		))

		await store.send(.closeActiveTabRequested) {
			$0 = TerminalTabs(
				sessions: [one],
				panes: [self.pane(one)],
				isPanelVisible: true,
				lastActiveSessionByRepo: [Self.alpha: one.id],
				recentSessionIds: [one.id]
			)
		}
	}

	@Test("⌘W closes a repository's last tab without asking while the panel has another pane")
	func closeActiveTabWithOtherPane() async {
		let alpha = session(Self.alpha)
		let beta = session(Self.beta)
		let store = makeStore(TerminalTabs(
			sessions: [alpha, beta],
			panes: [pane(alpha), pane(beta)],
			activePaneIndex: 1,
			isPanelVisible: true,
			lastActiveSessionByRepo: [Self.alpha: alpha.id, Self.beta: beta.id],
			recentSessionIds: [alpha.id, beta.id]
		))

		await store.send(.closeActiveTabRequested) {
			$0 = TerminalTabs(
				sessions: [alpha],
				panes: [self.pane(alpha)],
				isPanelVisible: true,
				lastActiveSessionByRepo: [Self.alpha: alpha.id],
				recentSessionIds: [alpha.id]
			)
		}
	}

	@Test("⌘W on a repository's last tab asks first, counting the other repositories with terminals")
	func closeActiveTabAsksOnLastTab() async {
		let alpha = session(Self.alpha)
		let betaOne = session(Self.beta, 1)
		let betaTwo = session(Self.beta, 2)
		let gamma = session("/repos/gamma")
		let store = makeStore(TerminalTabs(
			sessions: [alpha, betaOne, betaTwo, gamma],
			panes: [pane(alpha)],
			isPanelVisible: true
		))

		// The tab stays open until the user has answered. Repositories are counted, not tabs.
		await store.send(.closeActiveTabRequested)
		await store.receive(\.delegate, .lastTabCloseRequested(sessionId: alpha.id, otherRepositoryCount: 2))
	}

	@Test("⌘W on the only terminal there is does nothing")
	func closeActiveTabOnOnlyTerminal() async {
		let alpha = session(Self.alpha)
		let store = makeStore(TerminalTabs(sessions: [alpha], panes: [pane(alpha)], isPanelVisible: true))

		await store.send(.closeActiveTabRequested)
	}

	// MARK: - The panes

	@Test("interrupting types Ctrl-C into the named session")
	func interruptCallsPanes() async {
		let alpha = session(Self.alpha)
		let beta = session(Self.beta)
		let interrupted = LockIsolated<[UUID]>([])
		let store = makeStore(TerminalTabs(sessions: [alpha, beta], panes: [pane(alpha)], isPanelVisible: true)) {
			$0[TerminalPanesClient.self].interrupt = { sessionId in
				interrupted.withValue { $0.append(sessionId) }
			}
		}

		// The session is named: it need not be the one with the keyboard.
		await store.send(.interruptRequested(sessionId: beta.id))
		await store.finish()

		#expect(interrupted.value == [beta.id])
	}

	@Test("a find command goes to the pane with the keyboard")
	func findCallsPanesForActiveSession() async {
		let alpha = session(Self.alpha)
		let beta = session(Self.beta)
		let found = LockIsolated<[(command: TerminalFindCommand, sessionId: UUID)]>([])
		let store = makeStore(TerminalTabs(
			sessions: [alpha, beta],
			panes: [pane(alpha), pane(beta)],
			activePaneIndex: 1,
			isPanelVisible: true
		)) {
			$0[TerminalPanesClient.self].find = { command, sessionId in
				found.withValue { $0.append((command, sessionId)) }
			}
		}

		await store.send(.findRequested(.next))
		await store.finish()

		#expect(found.value.map(\.command) == [.next])
		#expect(found.value.map(\.sessionId) == [beta.id])
	}

	@Test("a find command with no terminal at the keyboard goes nowhere")
	func findNeedsActiveSession() async {
		let store = makeStore(TerminalTabs(sessions: [session(Self.alpha)]))

		await store.send(.findRequested(.show))
	}
}
