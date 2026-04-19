import ComposableArchitecture
import Foundation
import GitCore
import Settings

@Reducer
struct CreateWorktreeButtonReducer {
	@ObservableState
	struct State: Equatable {
		let repositoryPath: String
		@Shared(.worktreeBasePath)
		var worktreeBasePath = "../worktrees"
		@Shared(.groupSettings)
		var groupSettings: [String: RepoGroupSettings] = [:]
		var isCreating: Bool = false
		var showCreateDialog: Bool = false
		var branchName: String = ""
		var availableBranches: [BranchInfo] = []
		var selectedBaseBranch: String = "master"
		var branchSearchText: String = ""
		var isLoadingBranches: Bool = false

		var filteredBranches: [BranchInfo] {
			guard !branchSearchText.isEmpty else { return availableBranches }
			return availableBranches.filter {
				$0.name == selectedBaseBranch ||
				$0.name.localizedCaseInsensitiveContains(branchSearchText)
			}
		}
		var createNewBranch: Bool = true
		@Presents
		var errorAlert: AlertState<Action.ErrorAlert>?
	}

	enum Action: BindableAction {
		case binding(BindingAction<State>)
		case showDialog
		case cancelCreation
		case confirmCreation
		case errorAlert(PresentationAction<ErrorAlert>)
		case didCreateSuccessfully(copyResult: WorktreeFileCopier.Result?)
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
				state.branchSearchText = ""
				state.availableBranches = []
				return .none

			case .confirmCreation:
				guard !state.createNewBranch || !state.branchName.isEmpty else {
					return .none
				}

				state.showCreateDialog = false
				state.isCreating = true
				let copyPaths = state.groupSettings[state.repositoryPath]?.worktreeCopyPaths ?? []
				return .run { [
					branchName = state.branchName,
					baseBranch = state.selectedBaseBranch,
					path = state.repositoryPath,
					createNewBranch = state.createNewBranch,
					worktreeBasePath = state.worktreeBasePath,
					copyPaths
				] send in
					do {
						let worktreeURL = try await GitWorktreeCreator.createWorktree(
							branchName: branchName,
							baseBranch: baseBranch,
							repositoryPath: path,
							createNewBranch: createNewBranch,
							worktreeBasePath: worktreeBasePath
						)
						let copyResult: WorktreeFileCopier.Result? = copyPaths.isEmpty
							? nil
							: WorktreeFileCopier.copy(
								paths: copyPaths,
								from: URL(fileURLWithPath: path),
								to: worktreeURL
							)
						await send(.didCreateSuccessfully(copyResult: copyResult))
					}
					catch {
						await send(.didFailWithError(error.localizedDescription))
					}
				}

			case let .didCreateSuccessfully(copyResult):
				state.isCreating = false
				state.branchName = ""
				state.branchSearchText = ""
				state.availableBranches = []
				if let result = copyResult, result.hasWarnings {
					var lines: [String] = []
					if !result.missing.isEmpty {
						lines.append("Missing in source repository:")
						lines.append(contentsOf: result.missing.map { "  • \($0)" })
					}
					if !result.failed.isEmpty {
						if !lines.isEmpty { lines.append("") }
						lines.append("Failed to copy:")
						lines.append(contentsOf: result.failed.map { "  • \($0.path) — \($0.reason)" })
					}
					state.errorAlert = AlertState {
						TextState("Worktree created with warnings")
					} actions: {
						ButtonState(role: .cancel) {
							TextState("OK")
						}
					} message: {
						TextState(lines.joined(separator: "\n"))
					}
				}
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
