import ComposableArchitecture
import Foundation

@Reducer
struct TerminalLayoutReducer {
    @ObservableState
    struct State: Equatable {
        var activeRepositoryPath: String?

        @Presents
        var stagingDetail: RepositoryDetail.State?
    }

    enum Action {
        case selectRepo(repositoryPath: String)
        case hideTerminalMode
        case stagingButtonTapped(repositoryPath: String)
        case stagingDetail(PresentationAction<RepositoryDetail.Action>)
        case sessionStatusChanged(repositoryPath: String, status: TerminalSessionStatus)
        case killSession(repositoryPath: String)
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

            case .stagingDetail(.dismiss):
                return .none

            case .stagingDetail:
                return .none

            case .sessionStatusChanged:
                // Forwarded up to RepositoryListReducer
                return .none

            case .killSession:
                // Forwarded up to RepositoryListReducer
                return .none
            }
        }
        .ifLet(\.$stagingDetail, action: \.stagingDetail) {
            RepositoryDetail()
        }
    }
}
