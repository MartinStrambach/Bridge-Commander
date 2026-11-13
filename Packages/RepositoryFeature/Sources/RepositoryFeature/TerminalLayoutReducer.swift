import ComposableArchitecture
import Foundation
import GitCore
import GitGraphFeature
import Settings
import SimulatorFeature
import StagingFeature
import TerminalFeature

/// The terminal panel's toolbar and sheets: what exists only while the panel is on screen. The
/// tabs and panes are `TerminalWorkspaceReducer`'s, which outlives the panel being hidden; this
/// state is made when the panel is shown and dropped when it hides, which also cancels whatever
/// it had running.
@Reducer
struct TerminalLayoutReducer {
	@ObservableState
	struct State: Equatable {
		var isPushing = false
		var isFinishingMerge = false

		/// Written by the ⌘+/⌘−/⌘0 zoom actions. The panel view reads the same setting through its
		/// own `@Shared`, alongside the other terminal settings it resolves for the pane.
		@Shared(.terminalFontSize)
		var terminalFontSize = TerminalFontSize.default

		// No button state here: the toolbar scopes the opened row's own stores, so an operation
		// started from either view shows its progress in both, and hiding the panel (which drops
		// this state and cancels its effects) cannot kill it.

		/// The iOS simulator beside the terminal. Which repositories show it is a stored setting, so it survives
		/// this state being dropped when the panel hides.
		var simulatorPane = SimulatorPaneReducer.State()

		@Presents
		var stagingDetail: RepositoryDetail.State?

		@Presents
		var gitGraph: GitGraphReducer.State?
	}

	enum Action {
		case stagingButtonTapped(repositoryPath: String, iosSubfolderPath: String)
		case gitGraphButtonTapped(repositoryPath: String, repositoryName: String)
		case pushButtonTapped(repositoryPath: String)
		case pushCompleted(repositoryPath: String, result: GitPushHelper.PushResult?, error: GitError?)
		case finishMergeButtonTapped(repositoryPath: String)
		case finishMergeCompleted(repositoryPath: String, error: GitError?)
		case stagingDetail(PresentationAction<RepositoryDetail.Action>)
		case gitGraph(PresentationAction<GitGraphReducer.Action>)
		/// ⌘R: refreshes the row of the repository with the keyboard.
		case refreshActiveRepoRequested
		case zoomInRequested
		case zoomOutRequested
		case resetZoomRequested
		case simulatorPane(SimulatorPaneReducer.Action)
	}

	@Dependency(GitClient.self)
	private var gitClient

	var body: some Reducer<State, Action> {
		Scope(\.simulatorPane, action: \.simulatorPane) {
			SimulatorPaneReducer()
		}
		Reduce { state, action in
			switch action {
			case let .stagingButtonTapped(repositoryPath, iosSubfolderPath):
				state.stagingDetail = RepositoryDetail.State(repositoryPath: repositoryPath, iosSubfolderPath: iosSubfolderPath)
				return .none

			case let .gitGraphButtonTapped(repositoryPath, repositoryName):
				state.gitGraph = .forRepository(path: repositoryPath, name: repositoryName)
				return .none

			case let .pushButtonTapped(repositoryPath):
				state.isPushing = true
				return .run { [gitClient] send in
					do {
						let result = try await gitClient.push(repositoryPath)
						await send(.pushCompleted(repositoryPath: repositoryPath, result: result, error: nil))
					}
					catch let error as GitError {
						await send(.pushCompleted(repositoryPath: repositoryPath, result: nil, error: error))
					}
					catch {
						await send(.pushCompleted(repositoryPath: repositoryPath, result: nil, error: nil))
					}
				}

			case .pushCompleted:
				state.isPushing = false
				return .none

			case let .finishMergeButtonTapped(repositoryPath):
				state.isFinishingMerge = true
				return .run { [gitClient] send in
					do {
						try await gitClient.finishMerge(repositoryPath)
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

			case .stagingDetail,
			     .gitGraph:
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

			case .simulatorPane:
				return .none
			}
		}
		.ifLet(\.$stagingDetail, action: \.stagingDetail) {
			RepositoryDetail()
		}
		.ifLet(\.$gitGraph, action: \.gitGraph) {
			GitGraphReducer()
		}
	}
}
