import ActionButtons
import ComposableArchitecture
import Foundation
import TerminalFeature
import GitActionsMenu
import GitCore
import GitGraphFeature
import Settings
import SimulatorFeature
import StagingFeature

@Reducer
struct TerminalLayoutReducer {
	@ObservableState
	struct State: Equatable {
		var activeRepositoryPath: String?
		var activeSessionId: UUID?
		var isPushing = false
		var isFinishingMerge = false

		/// Written by the ⌘+/⌘−/⌘0 zoom actions. The panel view reads the same setting through its
		/// own `@Shared`, alongside the other terminal settings it resolves for the pane.
		@Shared(.terminalFontSize)
		var terminalFontSize = TerminalFontSize.default

		/// The tab that was last shown for each repository, so switching away from a
		/// repository and back reopens the tab the user left, not its first tab.
		var lastActiveSessionByRepo: [String: UUID] = [:]

		/// Every tab that has been on screen since the panel opened, most recent last, so closing
		/// the tab on screen goes back to the one the user was in before it.
		var recentSessionIds: [UUID] = []

		/// What the panel remembers about the tabs it has shown. Hiding the panel drops this whole
		/// state, so `RepositoryListReducer` keeps the memory meanwhile and hands it back to the
		/// next panel, which then reopens where the user left off.
		struct TabMemory: Equatable {
			var lastActiveSessionByRepo: [String: UUID] = [:]
			var recentSessionIds: [UUID] = []
		}

		var tabMemory: TabMemory {
			get {
				TabMemory(lastActiveSessionByRepo: lastActiveSessionByRepo, recentSessionIds: recentSessionIds)
			}
			set {
				lastActiveSessionByRepo = newValue.lastActiveSessionByRepo
				recentSessionIds = newValue.recentSessionIds
			}
		}

		/// Show `session` and remember it as the repository's current tab.
		mutating func activate(_ session: TerminalSession) {
			activeRepositoryPath = session.repositoryPath
			activeSessionId = session.id
			lastActiveSessionByRepo[session.repositoryPath] = session.id
			recentSessionIds.removeAll { $0 == session.id }
			recentSessionIds.append(session.id)
		}

		/// Drop a closed tab from the per-repository memory so it is never restored.
		mutating func forget(sessionId: UUID, repositoryPath: String) {
			if lastActiveSessionByRepo[repositoryPath] == sessionId {
				lastActiveSessionByRepo[repositoryPath] = nil
			}
			recentSessionIds.removeAll { $0 == sessionId }
		}

		/// Of `sessions`, the one most recently on screen — nil when none of them has been shown
		/// since the panel opened (tabs restored from the previous launch, say).
		func mostRecent(among sessions: some Collection<TerminalSession>) -> TerminalSession? {
			for id in recentSessionIds.reversed() {
				if let session = sessions.first(where: { $0.id == id }) {
					return session
				}
			}
			return nil
		}

		// The Xcode and Tuist buttons are deliberately not copied here: the toolbar scopes the
		// opened row's own stores, so a generate started from either view shows its progress in
		// both, and hiding the panel (which nils this state and cancels its effects) cannot kill it.
		var androidStudioButton: AndroidStudioButtonReducer.State?
		var webButton: WebButtonReducer.State?
		var ticketButton: TicketButtonReducer.State?
		var gitActionsMenu: GitActionsMenuReducer.State?

		/// The iOS simulator beside the terminal. Which repositories show it is a stored setting, so it survives
		/// this state being dropped when the panel hides.
		var simulatorPane = SimulatorPaneReducer.State()

		@Presents
		var stagingDetail: RepositoryDetail.State?

		@Presents
		var gitGraph: GitGraphReducer.State?
	}

	enum Action {
		case selectRepo(repositoryPath: String)
		case hideTerminalMode
		case stagingButtonTapped(repositoryPath: String, iosSubfolderPath: String)
		case gitGraphButtonTapped(repositoryPath: String, repositoryName: String)
		case pushButtonTapped(repositoryPath: String)
		case pushCompleted(result: GitPushHelper.PushResult?, error: GitError?)
		case finishMergeButtonTapped(repositoryPath: String)
		case finishMergeCompleted(repositoryPath: String, error: GitError?)
		case stagingDetail(PresentationAction<RepositoryDetail.Action>)
		case gitGraph(PresentationAction<GitGraphReducer.Action>)
		case killTab(sessionId: UUID)
		case closeActiveTabRequested
		case killRepo(repositoryPath: String)
		case newTabRequested
		case selectTab(sessionId: UUID)
		/// ⌃Tab / ⌃⇧Tab: the next or previous tab of the active repository, wrapping around.
		case cycleTabRequested(forward: Bool)
		/// A tab was dropped on another tab of the same repository and takes its place.
		case moveTab(sessionId: UUID, ontoSessionId: UUID)
		case retryTab(sessionId: UUID)
		case refreshActiveRepoRequested
		case zoomInRequested
		case zoomOutRequested
		case resetZoomRequested
		case androidStudioButton(AndroidStudioButtonReducer.Action)
		case webButton(WebButtonReducer.Action)
		case ticketButton(TicketButtonReducer.Action)
		case gitActionsMenu(GitActionsMenuReducer.Action)
		case simulatorPane(SimulatorPaneReducer.Action)
	}

	var body: some Reducer<State, Action> {
		Scope(\.simulatorPane, action: \.simulatorPane) {
			SimulatorPaneReducer()
		}
		// The core and its children are split into separate properties because
		// one long .ifLet chain exceeds the type-checker's expression budget.
		core
			.ifLet(\.$stagingDetail, action: \.stagingDetail) {
				RepositoryDetail()
			}
			.ifLet(\.$gitGraph, action: \.gitGraph) {
				GitGraphReducer()
			}
			.ifLet(\.gitActionsMenu, action: \.gitActionsMenu) {
				GitActionsMenuReducer()
			}
	}

	private var core: some Reducer<State, Action> {
		coreReduce
			.ifLet(\.androidStudioButton, action: \.androidStudioButton) {
				AndroidStudioButtonReducer()
			}
			.ifLet(\.webButton, action: \.webButton) {
				WebButtonReducer()
			}
			.ifLet(\.ticketButton, action: \.ticketButton) {
				TicketButtonReducer()
			}
	}

	private var coreReduce: some Reducer<State, Action> {
		Reduce { state, action in
			switch action {
			case let .selectRepo(repositoryPath):
				state.activeRepositoryPath = repositoryPath
				return .none

			case .hideTerminalMode:
				// Parent RepositoryListReducer handles this by setting terminalLayout = nil
				return .none

			case let .stagingButtonTapped(repositoryPath, iosSubfolderPath):
				state.stagingDetail = RepositoryDetail.State(repositoryPath: repositoryPath, iosSubfolderPath: iosSubfolderPath)
				return .none

			case let .gitGraphButtonTapped(repositoryPath, repositoryName):
				state.gitGraph = .forRepository(path: repositoryPath, name: repositoryName)
				return .none

			case let .pushButtonTapped(repositoryPath):
				state.isPushing = true
				return .run { send in
					do {
						let result = try await GitPushHelper.push(at: repositoryPath)
						await send(.pushCompleted(result: result, error: nil))
					}
					catch let error as GitError {
						await send(.pushCompleted(result: nil, error: error))
					}
					catch {
						await send(.pushCompleted(result: nil, error: nil))
					}
				}

			case .pushCompleted:
				state.isPushing = false
				return .none

			case let .finishMergeButtonTapped(repositoryPath):
				state.isFinishingMerge = true
				return .run { send in
					do {
						try await GitMergeHelper.finishMerge(at: repositoryPath)
						await send(.finishMergeCompleted(repositoryPath: repositoryPath, error: nil))
					}
					catch {
						let gitError = error as? GitError ?? .mergeFailed(error.localizedDescription)
						await send(.finishMergeCompleted(repositoryPath: repositoryPath, error: gitError))
					}
				}

			case .finishMergeCompleted:
				state.isFinishingMerge = false
				// Alert and row refresh are handled by RepositoryListReducer
				return .none

			case .stagingDetail(.dismiss):
				return .none

			case .stagingDetail:
				return .none

			case .gitGraph:
				return .none

			case .killTab:
				// Forwarded up to RepositoryListReducer
				return .none

			case .closeActiveTabRequested:
				// Forwarded up to RepositoryListReducer
				return .none

			case .killRepo:
				// Forwarded up to RepositoryListReducer
				return .none

			case .newTabRequested:
				// Forwarded up to RepositoryListReducer
				return .none

			case .selectTab:
				// Forwarded up to RepositoryListReducer
				return .none

			case .cycleTabRequested:
				// Forwarded up to RepositoryListReducer
				return .none

			case .moveTab:
				// Forwarded up to RepositoryListReducer
				return .none

			case .retryTab:
				// Forwarded up to RepositoryListReducer
				return .none

			case .refreshActiveRepoRequested:
				// Routed to a row refresh by RepositoryListReducer, which also re-detects the
				// row's Xcode project — the same state the toolbar's Xcode button shows.
				return .none

			// Zoom is stored, not per-pane: every terminal in the app renders at one size, and the
			// size the user zoomed to is still there after a restart — the same contract the
			// stepper in Settings writes to.
			case .zoomInRequested:
				state.$terminalFontSize.withLock { $0 = TerminalFontSize.zoomedIn(from: $0) }
				return .none

			case .zoomOutRequested:
				state.$terminalFontSize.withLock { $0 = TerminalFontSize.zoomedOut(from: $0) }
				return .none

			case .resetZoomRequested:
				state.$terminalFontSize.withLock { $0 = TerminalFontSize.default }
				return .none

			case .androidStudioButton:
				return .none

			case .webButton:
				return .none

			case .ticketButton:
				return .none

			case .gitActionsMenu:
				// Completions are routed to a row refresh by RepositoryListReducer
				return .none

			case .simulatorPane:
				return .none
			}
		}
	}
}
