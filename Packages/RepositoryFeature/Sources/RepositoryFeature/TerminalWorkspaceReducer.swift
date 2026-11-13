import ComposableArchitecture
import Foundation
import TerminalFeature

/// The tabs and panes of the terminal panel. Its state is `TerminalTabs`, which the repository
/// list always has — hiding the panel is a flag there, so the panes and the keyboard are where
/// they were when it is shown again.
///
/// Everything that needs only the tabs is done here: selecting, cycling, moving, focusing,
/// closing. What a new terminal runs and where it starts depends on the repository's settings,
/// which only `RepositoryListReducer` knows, so those intents go up as `Delegate.sessionRequested`
/// and come back as `sessionBuilt` with the session to place.
@Reducer
struct TerminalWorkspaceReducer {
	typealias State = TerminalTabs

	/// A terminal this reducer wants built.
	enum SessionRequest: Equatable {
		/// The first tab of a repository that has none.
		case firstTab(repositoryPath: String)
		/// A tab beside the ones the repository has, started in `directory` or at its root.
		case extraTab(repositoryPath: String, directory: String?)
		/// A fresh session in place of one whose shell failed.
		case replacement(of: TerminalSession)
	}

	/// Where a built session goes.
	enum Placement: Equatable {
		/// A tab of the active pane, shown, with the panel on screen.
		case tab
		/// A pane of its own to the right of the active one.
		case split
		/// The place of the session it replaces.
		case replacing(UUID)
	}

	enum Action {
		/// Shows a repository: the tab it was last showing, or its first one, opened now.
		case selectRepo(repositoryPath: String)
		case selectTab(sessionId: UUID)
		/// ⌃Tab / ⌃⇧Tab: the next or previous tab of the active pane, wrapping around.
		case cycleTabRequested(forward: Bool)
		/// A tab was dropped on another tab of the same pane and takes its place.
		case moveTab(sessionId: UUID, ontoSessionId: UUID)
		/// A pane was clicked and takes the keyboard.
		case paneFocused(sessionId: UUID)
		/// ⌘] / ⌘[: the next or previous pane, wrapping around.
		case cyclePaneRequested(forward: Bool)
		/// Takes a pane out of the split; its tabs stay open.
		case closePane(sessionId: UUID)
		/// Closes a tab, hanging its shell up.
		case killTab(sessionId: UUID)
		case killRepo(repositoryPath: String)
		/// ⌘W: closes the tab with the keyboard, or asks first when it is the last one.
		case closeActiveTabRequested
		/// ⌘T: another tab of the active repository.
		case newTabRequested
		/// ⌘D: a new pane beside the active one, up to `TerminalTabs.maxPanes`, with one tab: a
		/// new terminal of the active repository, opened where the active terminal's shell is.
		case splitRequested
		/// A repository in a pane of its own beside the active one, with its tabs: showing the
		/// one it was last showing, or its first one, opened now if it has none.
		case openRepoInSplit(repositoryPath: String)
		/// A fresh shell in the place of one that failed.
		case retryTab(sessionId: UUID)
		/// The answer to `Delegate.sessionRequested`.
		case sessionBuilt(TerminalSession, Placement)
		/// Types Ctrl-C into a session, stopping what runs in it without closing its tab.
		case interruptRequested(sessionId: UUID)
		/// A find command for the pane with the keyboard.
		case findRequested(TerminalFindCommand)
		case hidePanelRequested
		case delegate(Delegate)

		@CasePathable
		enum Delegate: Equatable {
			/// Build this session and answer with `sessionBuilt`, passing the placement back.
			case sessionRequested(SessionRequest, Placement)
			/// ⌘W on a repository's last tab while other repositories have terminals running:
			/// the user has to say whether they mean this tab or the app.
			case lastTabCloseRequested(sessionId: UUID, otherRepositoryCount: Int)
		}
	}

	@Dependency(TerminalPanesClient.self)
	private var panes

	var body: some Reducer<State, Action> {
		Reduce { state, action in
			switch action {
			case let .selectRepo(repositoryPath):
				guard let existing = state.lastActiveSession(for: repositoryPath) else {
					return .send(.delegate(.sessionRequested(.firstTab(repositoryPath: repositoryPath), .tab)))
				}

				state.show(existing)
				state.showPanel()
				return .none

			case let .selectTab(sessionId):
				if let session = state.sessions[id: sessionId] {
					state.show(session)
				}
				return .none

			// ⌃Tab / ⌃⇧Tab, as in Terminal.app: step through the tabs the bar shows, wrapping at
			// either end. Like ⌘W it names no session and resolves the active tab when it fires,
			// so a stale closure cannot misfire.
			case let .cycleTabRequested(forward):
				state.cycleTab(forward: forward)
				return .none

			case let .moveTab(sessionId, ontoSessionId):
				state.moveTab(sessionId, onto: ontoSessionId)
				return .none

			case let .paneFocused(sessionId):
				state.focusPane(sessionId)
				return .none

			case let .cyclePaneRequested(forward):
				state.cyclePane(forward: forward)
				return .none

			case let .closePane(sessionId):
				state.closePane(sessionId)
				return .none

			// The shells are hung up by `RepositoryListReducer` once the sessions have left the
			// state, whichever way they left it.
			case let .killTab(sessionId):
				state.close([sessionId])
				return .none

			case let .killRepo(repositoryPath):
				state.close(state.tabs(of: repositoryPath).map(\.id))
				return .none

			// ⌘W names no session: it closes whichever tab is active at the moment it fires.
			// The shortcut used to hand `killTab` the id captured when its hidden button was
			// laid out, and SwiftUI kept firing that first closure — so the second press asked
			// to kill a session that had already left the state and did nothing, for good.
			// Resolving the target here cannot go stale.
			// While the repo has a second tab to fall back to, or the panel another pane, this
			// just closes the active one. On the repo's *last* tab with nothing beside it, it
			// asks first, because the two things the user could mean are far apart: leave this
			// repo (other repos still have terminals running, and the panel would switch to one
			// of them) or quit the app outright, which is what ⌘W does on the last tab when
			// nothing else is running — the shortcut is left unregistered there so it falls
			// through to File ▸ Close.
			case .closeActiveTabRequested:
				guard let session = state.activeSession else {
					return .none
				}

				let path = session.repositoryPath
				if state.tabs(of: path).count > 1 || state.panes.count > 1 {
					state.close([session.id])
					return .none
				}
				let otherRepositoryCount = Set(state.sessions.map(\.repositoryPath).filter { $0 != path }).count
				guard otherRepositoryCount > 0 else {
					// No other terminals to keep the app open for — leave it to File ▸ Close.
					return .none
				}

				return .send(.delegate(.lastTabCloseRequested(
					sessionId: session.id,
					otherRepositoryCount: otherRepositoryCount
				)))

			case .newTabRequested:
				guard let path = state.activeRepositoryPath else {
					return .none
				}

				return .send(.delegate(.sessionRequested(.extraTab(repositoryPath: path, directory: nil), .tab)))

			// Like any extra tab the new pane's is a plain shell unless the startup command is
			// wanted in new tabs. The directory is read when the split is asked for: it is
			// wherever the active terminal's shell is by then.
			case .splitRequested:
				guard state.canSplit, let active = state.activeSession else {
					return .none
				}

				return .run { [panes] send in
					let directory = await panes.currentDirectory(active.id)
					await send(.delegate(.sessionRequested(
						.extraTab(repositoryPath: active.repositoryPath, directory: directory),
						.split
					)))
				}

			case let .openRepoInSplit(repositoryPath):
				guard let existing = state.lastActiveSession(for: repositoryPath) else {
					return .send(.delegate(.sessionRequested(.firstTab(repositoryPath: repositoryPath), .split)))
				}

				state.split(showing: existing)
				return .none

			case let .retryTab(sessionId):
				guard let old = state.sessions[id: sessionId] else {
					return .none
				}

				return .send(.delegate(.sessionRequested(.replacement(of: old), .replacing(sessionId))))

			case let .sessionBuilt(session, placement):
				switch placement {
				case .tab:
					state.open(session)
					state.showPanel()

				case .split:
					state.split(showing: session)

				// In the old one's place, not appended: the tab bar lays tabs out in array
				// order, so appending moved the retried tab to the end of the bar.
				case let .replacing(sessionId):
					state.replace(sessionId, with: session)
					state.show(session)
				}
				return .none

			case let .interruptRequested(sessionId):
				return .run { [panes] _ in
					await panes.interrupt(sessionId)
				}

			// The session is resolved when the key is pressed, for the reason ⌘W documents.
			case let .findRequested(command):
				guard let sessionId = state.activeSessionId else {
					return .none
				}

				return .run { [panes] _ in
					await panes.find(command, sessionId)
				}

			case .hidePanelRequested:
				state.hidePanel()
				return .none

			case .delegate:
				return .none
			}
		}
	}
}
