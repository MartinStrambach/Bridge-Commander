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

		var xcodeButton: XcodeProjectButtonReducer.State?
		var androidStudioButton: AndroidStudioButtonReducer.State?

		@Presents
		var stagingDetail: RepositoryDetail.State?
	}

	enum Action {
		case selectRepo(repositoryPath: String)
		case hideTerminalMode
		case stagingButtonTapped(repositoryPath: String, iosSubfolderPath: String)
		case pushButtonTapped(repositoryPath: String)
		case pushCompleted(result: GitPushHelper.PushResult?, error: GitError?)
		case stagingDetail(PresentationAction<RepositoryDetail.Action>)
		case sessionStatusChanged(sessionId: UUID, status: TerminalSessionStatus)
		case killTab(sessionId: UUID)
		case killRepo(repositoryPath: String)
		case newTabRequested
		case selectTab(sessionId: UUID)
		case retryTab(sessionId: UUID)
		case xcodeButton(XcodeProjectButtonReducer.Action)
		case androidStudioButton(AndroidStudioButtonReducer.Action)
	}

	var body: some Reducer<State, Action> {
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

			case .stagingDetail(.dismiss):
				return .none

			case .stagingDetail:
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

			case .xcodeButton:
				return .none

			case .androidStudioButton:
				return .none
			}
		}
		.ifLet(\.$stagingDetail, action: \.stagingDetail) {
			RepositoryDetail()
		}
		.ifLet(\.xcodeButton, action: \.xcodeButton) {
			XcodeProjectButtonReducer()
		}
		.ifLet(\.androidStudioButton, action: \.androidStudioButton) {
			AndroidStudioButtonReducer()
		}
	}
}
