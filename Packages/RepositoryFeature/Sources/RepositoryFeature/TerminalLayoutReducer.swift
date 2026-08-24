import ActionButtons
import ComposableArchitecture
import Foundation
import TerminalFeature
import GitCore

@Reducer
struct TerminalLayoutReducer {
	@ObservableState
	struct State: Equatable {
		var activeRepositoryPath: String?
		var activeSessionId: UUID?
		var isPushing = false
		var isFinishingMerge = false

		var xcodeButton: XcodeProjectButtonReducer.State?
		var androidStudioButton: AndroidStudioButtonReducer.State?
		var webButton: WebButtonReducer.State?
		var tuistButton: TuistButtonReducer.State?
		var ticketButton: TicketButtonReducer.State?

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
		case sessionStatusChanged(sessionId: UUID, status: TerminalSessionStatus)
		case killTab(sessionId: UUID)
		case killRepo(repositoryPath: String)
		case newTabRequested
		case selectTab(sessionId: UUID)
		case retryTab(sessionId: UUID)
		case refreshActiveRepoRequested
		case xcodeButton(XcodeProjectButtonReducer.Action)
		case androidStudioButton(AndroidStudioButtonReducer.Action)
		case webButton(WebButtonReducer.Action)
		case tuistButton(TuistButtonReducer.Action)
		case ticketButton(TicketButtonReducer.Action)
	}

	var body: some Reducer<State, Action> {
		// The core and its children are split into separate properties because
		// one long .ifLet chain exceeds the type-checker's expression budget.
		core
			.ifLet(\.$stagingDetail, action: \.stagingDetail) {
				RepositoryDetail()
			}
			.ifLet(\.$gitGraph, action: \.gitGraph) {
				GitGraphReducer()
			}
	}

	private var core: some Reducer<State, Action> {
		coreReduce
			.ifLet(\.xcodeButton, action: \.xcodeButton) {
				XcodeProjectButtonReducer()
			}
			.ifLet(\.androidStudioButton, action: \.androidStudioButton) {
				AndroidStudioButtonReducer()
			}
			.ifLet(\.webButton, action: \.webButton) {
				WebButtonReducer()
			}
			.ifLet(\.tuistButton, action: \.tuistButton) {
				TuistButtonReducer()
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
				state.gitGraph = GitGraphReducer.State(repositoryPath: repositoryPath, repositoryName: repositoryName)
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

			case .sessionStatusChanged:
				// Forwarded up to RepositoryListReducer
				return .none

			case .killTab:
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

			case .retryTab:
				// Forwarded up to RepositoryListReducer
				return .none

			case .refreshActiveRepoRequested:
				// The row refresh is routed by RepositoryListReducer. The toolbar's Xcode
				// button is a copy of the row's state (synced only on open/selectRepo), so it
				// must re-detect the project on disk itself — otherwise a project generated
				// while the terminal is open never shows up here.
				guard state.xcodeButton != nil else {
					return .none
				}
				return .send(.xcodeButton(.refresh))

			case .xcodeButton:
				return .none

			case .androidStudioButton:
				return .none

			case .webButton:
				return .none

			case .tuistButton:
				return .none

			case .ticketButton:
				return .none
			}
		}
	}
}
