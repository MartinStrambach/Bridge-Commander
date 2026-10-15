import ComposableArchitecture
import Foundation
import GitCore

// MARK: - Checkout Default Branch Button Reducer

@Reducer
public struct CheckoutDefaultBranchButtonReducer {
	@ObservableState
	public struct State: Equatable {
		var isCheckingOut = false
		/// Set alongside `isCheckingOut` by "Checkout & Pull", for the progress text.
		var isPullingAfterCheckout = false
		/// Per-group configured default branch. Empty = auto-detect (origin/HEAD, then master/main).
		var defaultBranch: String

		fileprivate let repositoryPath: String

		init(repositoryPath: String, defaultBranch: String = "") {
			self.repositoryPath = repositoryPath
			self.defaultBranch = defaultBranch
		}
	}

	/// What "Checkout & Pull" did once the checkout succeeded. The pull can still fail
	/// (no upstream, diverged history); the branch was switched either way.
	public struct CheckoutAndPullResult: Equatable {
		public let branch: String
		public let pull: Result<GitPullHelper.PullResult, GitError>
	}

	public enum Action: Equatable {
		case checkoutTapped
		case checkoutAndPullTapped
		/// On success carries the branch git actually switched to: an empty setting is
		/// auto-detected, so the state alone can't name it.
		case checkoutCompleted(result: Result<String, GitError>)
		/// Failure means the checkout itself failed and nothing was pulled.
		case checkoutAndPullCompleted(result: Result<CheckoutAndPullResult, GitError>)
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
					catch {
						await send(.checkoutCompleted(result: .failure(Self.gitError(error))))
					}
				}

			case .checkoutAndPullTapped:
				state.isCheckingOut = true
				state.isPullingAfterCheckout = true
				return .run { [path = state.repositoryPath, baseBranch = state.defaultBranch, gitClient] send in
					let branch: String
					do {
						branch = try await gitClient.checkoutDefaultBranch(at: path, baseBranch: baseBranch)
					}
					catch {
						await send(.checkoutAndPullCompleted(result: .failure(Self.gitError(error))))
						return
					}

					let pull: Result<GitPullHelper.PullResult, GitError>
					do {
						pull = try await .success(gitClient.pull(at: path))
					}
					catch let error as GitError {
						pull = .failure(error)
					}
					catch {
						print("Unexpected error during pull: \(error)")
						pull = .failure(.pullFailed(error.localizedDescription))
					}
					await send(.checkoutAndPullCompleted(result: .success(CheckoutAndPullResult(branch: branch, pull: pull))))
				}

			case .checkoutCompleted, .checkoutAndPullCompleted:
				state.isCheckingOut = false
				state.isPullingAfterCheckout = false
				return .none
			}
		}
	}

	private static func gitError(_ error: any Error) -> GitError {
		if let error = error as? GitError {
			return error
		}
		print("Unexpected error during checkout: \(error)")
		return .checkoutFailed(error.localizedDescription)
	}
}
