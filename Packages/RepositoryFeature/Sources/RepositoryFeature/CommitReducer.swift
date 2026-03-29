import ComposableArchitecture
import Foundation
import AppUI
import GitCore

@Reducer
struct CommitReducer {
	@ObservableState
	struct State: Equatable {
		let repositoryPath: String
		var message: String = ""
		var isCommitting: Bool = false
		var shouldPushAfterCommit: Bool = false
		@Presents
		var alert: GitAlertReducer.State?
	}

	enum Action: BindableAction {
		case binding(BindingAction<State>)
		case commitTapped
		case commitAndPushTapped
		case cancelTapped
		case commitCompleted(Result<Void, Error>)
		case pushCompleted(Result<Void, Error>)
		case alert(PresentationAction<GitAlertReducer.Action>)
		case delegate(Delegate)

		enum Delegate {
			case commitSucceeded
		}
	}

	@Dependency(GitStagingClient.self)
	private var gitStagingClient

	@Dependency(\.dismiss)
	private var dismiss

	var body: some Reducer<State, Action> {
		BindingReducer()
		Reduce { state, action in
			switch action {
			case .commitTapped:
				guard !state.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
					return .none
				}

				state.isCommitting = true
				state.shouldPushAfterCommit = false
				return .run { [path = state.repositoryPath, message = state.message] send in
					await send(.commitCompleted(Result { try await gitStagingClient.commit(path, message) }))
				}

			case .commitAndPushTapped:
				guard !state.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
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
							_ = try await GitPushHelper.push(at: path)
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
				state.isCommitting = false
				state.alert = GitAlertReducer.State(
					title: "Push Failed",
					message: error.localizedDescription,
					isError: true
				)
				return .none

			case let .commitCompleted(.failure(error)):
				state.isCommitting = false
				state.shouldPushAfterCommit = false
				state.alert = GitAlertReducer.State(
					title: "Commit Failed",
					message: error.localizedDescription,
					isError: true
				)
				return .none

			case .cancelTapped:
				return .run { _ in await dismiss() }

			case .alert,
			     .binding,
			     .delegate:
				return .none
			}
		}
		.ifLet(\.$alert, action: \.alert) {
			GitAlertReducer()
		}
	}
}
