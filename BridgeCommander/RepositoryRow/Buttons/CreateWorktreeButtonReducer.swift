import ComposableArchitecture
import Foundation

@Reducer
struct CreateWorktreeButtonReducer {
	@ObservableState
	struct State: Equatable {
		let repositoryPath: String
		var isCreating: Bool = false
		var showCreateDialog: Bool = false
		var branchName: String = ""
		var availableBranches: [BranchInfo] = []
		var selectedBaseBranch: String = "master"
		var isLoadingBranches: Bool = false
		@Presents
		var errorAlert: AlertState<Action.ErrorAlert>?
	}

	enum Action: BindableAction {
		case binding(BindingAction<State>)
		case showDialog
		case cancelCreation
		case confirmCreation
		case errorAlert(PresentationAction<ErrorAlert>)
		case didCreateSuccessfully
		case didFailWithError(String)
		case loadBranches
		case branchesLoaded([BranchInfo])

		enum ErrorAlert: Equatable {}
	}

	var body: some Reducer<State, Action> {
		BindingReducer()
		Reduce { state, action in
			switch action {
			case .showDialog:
				state.showCreateDialog = true
				state.branchName = ""
				return .send(.loadBranches)

			case .loadBranches:
				state.isLoadingBranches = true
				return .run { [path = state.repositoryPath] send in
					let branches = await GitBranchListHelper.listBranchesWithInfo(at: path)
					await send(.branchesLoaded(branches))
				}

			case let .branchesLoaded(branches):
				state.availableBranches = branches
				state.isLoadingBranches = false
				// Set default to master or main if available
				let branchNames = branches.map(\.name)
				if branchNames.contains("master") {
					state.selectedBaseBranch = "master"
				}
				else if branchNames.contains("main") {
					state.selectedBaseBranch = "main"
				}
				else if let first = branchNames.first {
					state.selectedBaseBranch = first
				}
				return .none

			case .cancelCreation:
				state.showCreateDialog = false
				state.branchName = ""
				state.availableBranches = []
				return .none

			case .confirmCreation:
				guard !state.branchName.isEmpty else {
					return .none
				}

				state.showCreateDialog = false
				state.isCreating = true
				return .run { [
					branchName = state.branchName,
					baseBranch = state.selectedBaseBranch,
					path = state.repositoryPath
				] send in
					do {
						try await GitWorktreeCreator.createWorktree(
							branchName: branchName,
							baseBranch: baseBranch,
							repositoryPath: path
						)
						await send(.didCreateSuccessfully)
					}
					catch {
						await send(.didFailWithError(error.localizedDescription))
					}
				}

			case .didCreateSuccessfully:
				state.isCreating = false
				state.branchName = ""
				state.availableBranches = []
				return .none

			case let .didFailWithError(error):
				state.isCreating = false
				state.errorAlert = AlertState {
					TextState("Creation Error")
				} actions: {
					ButtonState(role: .cancel) {
						TextState("OK")
					}
				} message: {
					TextState(error)
				}
				return .none

			case .errorAlert:
				return .none

			default:
				return .none
			}
		}
		.ifLet(\.$errorAlert, action: \.errorAlert)
	}
}
