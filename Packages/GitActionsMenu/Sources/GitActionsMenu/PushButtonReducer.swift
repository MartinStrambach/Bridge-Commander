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
		/// Offered by the "Push Failed" alert when git refused a plain push as non-fast-forward.
		case forcePushTapped(GitRejectedPush)
		case pushCompleted(result: GitPushHelper.PushResult?, error: GitError?)
	}

	/// What the "Push Failed" alert adds below git's output when it offers a force push. Shared
	/// with the terminal toolbar's Push button, whose alert offers the same.
	public static func forcePushExplanation(for rejected: GitRejectedPush) -> String {
		let remote = rejected.remoteBranch == rejected.localBranch
			? "the remote \(rejected.remoteBranch)"
			: "the remote \(rejected.remoteBranch) (pushed from \(rejected.localBranch))"
		return """
		\(remote.prefix(1).uppercased() + remote.dropFirst()) has commits your branch doesn't, which \
		is expected after a rebase or an amend. Force Push replaces it with your \
		\(rejected.localBranch). It stops instead if the remote has commits you haven't fetched or \
		haven't built on.
		"""
	}

	@Dependency(GitClient.self)
	private var gitClient

	public var body: some Reducer<State, Action> {
		Reduce { state, action in
			switch action {
			case .pushTapped:
				return push(&state, mode: .normal)

			case let .forcePushTapped(rejected):
				return push(&state, mode: .forceWithLease(rejected))

			case .pushCompleted:
				state.isPushing = false
				return .none
			}
		}
	}

	private func push(_ state: inout State, mode: GitPushHelper.Mode) -> Effect<Action> {
		state.isPushing = true
		return .run { [path = state.repositoryPath, gitClient] send in
			do {
				let result = try await gitClient.push(at: path, mode: mode)
				await send(.pushCompleted(result: result, error: nil))
			}
			catch {
				let gitError = error as? GitError ?? .pushFailed(error.localizedDescription)
				await send(.pushCompleted(result: nil, error: gitError))
			}
		}
	}
}
