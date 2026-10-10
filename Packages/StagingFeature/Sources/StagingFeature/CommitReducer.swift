import ComposableArchitecture
import Foundation
import AppUI
import GitCore

@Reducer
public struct CommitReducer: Sendable {
	@ObservableState
	public struct State: Equatable {
		let repositoryPath: String
		var message: String = ""
		var isCommitting: Bool = false
		var shouldPushAfterCommit: Bool = false
		/// The commit landed but the push after it failed: the sheet stays only to show the push
		/// error, takes no second commit, and closes once the error is acknowledged.
		var hasCommitted: Bool = false
		@Presents
		var alert: ScrollableAlertReducer.State?
	}

	public enum Action: BindableAction {
		case binding(BindingAction<State>)
		case commitTapped
		case commitAndPushTapped
		case cancelTapped
		case commitCompleted(Result<Void, Error>)
		case pushCompleted(Result<Void, Error>)
		case alert(PresentationAction<ScrollableAlertReducer.Action>)
		case delegate(Delegate)

		@CasePathable
		public enum Delegate {
			case commitSucceeded
		}
	}

	@Dependency(GitStagingClient.self)
	private var gitStagingClient

	@Dependency(GitClient.self)
	private var gitClient

	@Dependency(\.dismiss)
	private var dismiss

	public var body: some Reducer<State, Action> {
		BindingReducer()
		Reduce { state, action in
			switch action {
			case .commitTapped:
				guard
					!state.isCommitting,
					!state.hasCommitted,
					!state.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
				else {
					return .none
				}

				state.isCommitting = true
				state.shouldPushAfterCommit = false
				return .run { [path = state.repositoryPath, message = state.message] send in
					await send(.commitCompleted(Result { try await gitStagingClient.commit(path, message) }))
				}

			case .commitAndPushTapped:
				guard
					!state.isCommitting,
					!state.hasCommitted,
					!state.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
				else {
					return .none
				}

				state.isCommitting = true
				state.shouldPushAfterCommit = true
				return .run { [path = state.repositoryPath, message = state.message] send in
					await send(.commitCompleted(Result { try await gitStagingClient.commit(path, message) }))
				}

			case .commitCompleted(.success):
				if state.shouldPushAfterCommit {
					return .run { [path = state.repositoryPath] send in
						await send(.pushCompleted(Result {
							_ = try await gitClient.push(path)
						}))
					}
				}
				state.isCommitting = false
				return .run { send in
					await send(.delegate(.commitSucceeded))
					await dismiss()
				}

			case .pushCompleted(.success):
				state.isCommitting = false
				return .run { send in
					await send(.delegate(.commitSucceeded))
					await dismiss()
				}

			case let .pushCompleted(.failure(error)):
				// The commit is in, so the panel must refresh now, not only after a successful push.
				state.isCommitting = false
				state.hasCommitted = true
				state.alert = ScrollableAlertReducer.State(
					title: "Push Failed",
					message: error.localizedDescription,
					isError: true
				)
				return .send(.delegate(.commitSucceeded))

			case let .commitCompleted(.failure(error)):
				state.isCommitting = false
				state.shouldPushAfterCommit = false
				state.alert = ScrollableAlertReducer.State(
					title: "Commit Failed",
					message: error.localizedDescription,
					isError: true
				)
				return .none

			case .cancelTapped:
				return .run { _ in await dismiss() }

			case .alert(.dismiss) where state.hasCommitted:
				return .run { _ in await dismiss() }

			case .alert,
			     .binding,
			     .delegate:
				return .none
			}
		}
		.ifLet(\.$alert, action: \.alert) {
			ScrollableAlertReducer()
		}
	}
}
