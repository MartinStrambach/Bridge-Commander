import ComposableArchitecture
import Foundation

@Reducer
struct TerminalLayoutReducer {
    @ObservableState
    struct State: Equatable {
        var activeRepositoryPath: String?
        var activeSessionId: UUID?
        var isPushing = false

        @Presents
        var stagingDetail: RepositoryDetail.State?
    }

    enum Action {
        case selectRepo(repositoryPath: String)
        case hideTerminalMode
        case stagingButtonTapped(repositoryPath: String)
        case pushButtonTapped(repositoryPath: String)
        case pushCompleted(result: GitPushHelper.PushResult?, error: GitError?)
        case stagingDetail(PresentationAction<RepositoryDetail.Action>)
        case sessionStatusChanged(sessionId: UUID, status: TerminalSessionStatus)
        case killTab(sessionId: UUID)
        case killRepo(repositoryPath: String)
        case newTabRequested
        case selectTab(sessionId: UUID)
        case retryTab(sessionId: UUID)
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

            case let .stagingButtonTapped(repositoryPath):
                state.stagingDetail = RepositoryDetail.State(repositoryPath: repositoryPath)
                return .none

            case let .pushButtonTapped(repositoryPath):
                state.isPushing = true
                return .run { send in
                    do {
                        let result = try await GitPushHelper.push(at: repositoryPath)
                        await send(.pushCompleted(result: result, error: nil))
                    } catch let error as GitError {
                        await send(.pushCompleted(result: nil, error: error))
                    } catch {
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
            }
        }
        .ifLet(\.$stagingDetail, action: \.stagingDetail) {
            RepositoryDetail()
        }
    }
}
