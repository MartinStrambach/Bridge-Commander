import ComposableArchitecture
import Foundation
import GitCore

// MARK: - Push Button Reducer

@Reducer
public struct PushButtonReducer {
	@ObservableState
	public struct State: Equatable {
		let repositoryPath: String
		var isPushing = false
	}

	public enum Action: Equatable {
		case pushTapped
		/// A push whose success is not alerted (the terminal toolbar's Push button: the count it
		/// shows dropping is the confirmation). Failures still are.
		case quietPushTapped
		/// `quiet` rides along from the tap rather than living in the state, so it cannot outlast
		/// the push it was asked for.
		case pushCompleted(result: GitPushHelper.PushResult?, error: GitError?, quiet: Bool = false)
	}

	@Dependency(GitClient.self)
	private var gitClient

	public var body: some Reducer<State, Action> {
		Reduce { state, action in
			switch action {
			case .pushTapped:
				return push(&state, quiet: false)

			case .quietPushTapped:
				return push(&state, quiet: true)

			case .pushCompleted:
				state.isPushing = false
				return .none
			}
		}
	}

	private func push(_ state: inout State, quiet: Bool) -> Effect<Action> {
		state.isPushing = true
		return .run { [path = state.repositoryPath, gitClient] send in
			do {
				let result = try await gitClient.push(at: path)
				await send(.pushCompleted(result: result, error: nil, quiet: quiet))
			}
			catch let error as GitError {
				await send(.pushCompleted(result: nil, error: error, quiet: quiet))
			}
			catch {
				print("Unexpected error during push: \(error)")
				await send(.pushCompleted(result: nil, error: nil, quiet: quiet))
			}
		}
	}
}
