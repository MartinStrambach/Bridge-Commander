import ComposableArchitecture
import Foundation
import GitCore

// MARK: - Checkout Default Branch Button Reducer

@Reducer
public struct CheckoutDefaultBranchButtonReducer {
	@ObservableState
	public struct State: Equatable {
		var isCheckingOut = false
		/// Per-group configured default branch. Empty = auto-detect (origin/HEAD, then master/main).
		var defaultBranch: String

		fileprivate let repositoryPath: String

		init(repositoryPath: String, defaultBranch: String = "") {
			self.repositoryPath = repositoryPath
			self.defaultBranch = defaultBranch
		}
	}

	public enum Action: Equatable {
		case checkoutTapped
		/// On success carries the branch git actually switched to: an empty setting is
		/// auto-detected, so the state alone can't name it.
		case checkoutCompleted(result: Result<String, GitError>)
	}

	@Dependency(GitClient.self)
	private var gitClient

	public var body: some Reducer<State, Action> {
		Reduce { state, action in
			switch action {
			case .checkoutTapped:
				state.isCheckingOut = true
				return .run { [path = state.repositoryPath, baseBranch = state.defaultBranch, gitClient] send in
					do {
						let branch = try await gitClient.checkoutDefaultBranch(at: path, baseBranch: baseBranch)
						await send(.checkoutCompleted(result: .success(branch)))
					}
					catch let error as GitError {
						await send(.checkoutCompleted(result: .failure(error)))
					}
					catch {
						print("Unexpected error during checkout: \(error)")
						await send(.checkoutCompleted(result: .failure(.checkoutFailed(error.localizedDescription))))
					}
				}

			case .checkoutCompleted:
				state.isCheckingOut = false
				return .none
			}
		}
	}
}
