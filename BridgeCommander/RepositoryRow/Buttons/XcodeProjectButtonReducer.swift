import ComposableArchitecture
import Foundation

// MARK: - Xcode Project Button Reducer

@Reducer
struct XcodeProjectButtonReducer {
	@ObservableState
	struct State: Equatable {
		let repositoryPath: String
		var projectState: XcodeProjectState = .checking
		var projectPath: String?
		var showingWarning: Bool = false
		var errorMessage: String? = nil
	}

	enum Action {
		case onAppear
		case foundProjectPath(String?)
		case openProject
		case didOpenProject
		case openFailed(String)
		case generateProject
		case projectGenerationProgress(XcodeProjectState)
		case didGenerateProject(String)
		case generationFailed(String)
		case dismissWarning
		case dismissError
	}

	@Dependency(\.xcodeService)
	private var xcodeService

	var body: some Reducer<State, Action> {
		Reduce { state, action in
			switch action {
			case .onAppear:
				return .run { [path = state.repositoryPath] send in
					let projectPath = await xcodeService.findXcodeProject(in: path)
					await send(.foundProjectPath(projectPath))
				}

			case let .foundProjectPath(path):
				state.projectState = .idle
				state.projectPath = path
				return .none

			case .openProject:
				guard let projectPath = state.projectPath else {
					return .send(.generateProject)
				}
				state.projectState = .opening

				return .run { send in
					do {
						try await XcodeProjectGenerator.openProject(at: projectPath)
						await send(.didOpenProject)
					}
					catch {
						await send(.openFailed(error.localizedDescription))
					}
				}

			case .didOpenProject:
				state.projectState = .idle
				return .none

			case let .openFailed(error):
				state.projectState = .error(error)
				state.errorMessage = error
				return .none

			case .generateProject:
				return .run { [path = state.repositoryPath] send in
					do {
						let projectPath = try await XcodeProjectGenerator.generateProject(at: path) { newState in
							Task {
								await send(.projectGenerationProgress(newState))
							}
						}
						await send(.didGenerateProject(projectPath))
					}
					catch {
						await send(.generationFailed(error.localizedDescription))
					}
				}

			case let .projectGenerationProgress(newState):
				state.projectState = newState
				return .none

			case let .didGenerateProject(projectPath):
				state.projectPath = projectPath
				return .run { send in
					await send(.openProject)
				}

			case let .generationFailed(error):
				state.projectState = .error(error)
				state.errorMessage = error
				return .none

			case .dismissWarning:
				state.showingWarning = false
				state.projectState = .idle
				return .none

			case .dismissError:
				state.errorMessage = nil
				state.projectState = .idle
				return .none
			}
		}
	}
}
