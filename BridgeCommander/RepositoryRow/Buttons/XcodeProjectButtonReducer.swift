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
		@Shared(.iosSubfolderPath)
		var iosSubfolderPath = "ios/FlashScore"
		@Shared(.openXcodeAfterGenerate)
		var openXcodeAfterGenerate = true
		@Presents
		var alert: AlertState<Action.Alert>?
	}

	enum Action {
		case onAppear
		case foundProjectPath(String?)
		case openProject
		case didOpenProject
		case openFailed(String)
		case projectGenerationProgress(XcodeProjectState)
		case didGenerateProject(String)
		case generationFailed(String)
		case alert(PresentationAction<Alert>)

		enum Alert: Equatable {
			case confirmGenerate
		}
	}

	@Dependency(XcodeClient.self)
	private var xcodeClient

	var body: some Reducer<State, Action> {
		Reduce { state, action in
			switch action {
			case .onAppear:
				return .run { [path = state.repositoryPath, iosSubfolderPath = state.iosSubfolderPath] send in
					let projectPath = await xcodeClient.findXcodeProject(in: path, iosSubfolderPath: iosSubfolderPath)
					await send(.foundProjectPath(projectPath))
				}

			case let .foundProjectPath(path):
				state.projectState = .idle
				state.projectPath = path
				return .none

			case .openProject:
				guard let projectPath = state.projectPath else {
					// Show warning alert asking to generate
					state.alert = AlertState {
						TextState("No Xcode Project Found")
					} actions: {
						ButtonState(role: .cancel) {
							TextState("Cancel")
						}
						ButtonState(action: .confirmGenerate) {
							TextState("Generate")
						}
					} message: {
						TextState("No Xcode project or workspace was found.\n\nWould you like to generate one?")
					}
					return .none
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
				state.alert = .okAlert(
					title: "Failed to Open Xcode Project",
					message: error
				)
				return .none

			case .alert(.presented(.confirmGenerate)):
				return .run { [
					path = state.repositoryPath,
					iosSubfolderPath = state.iosSubfolderPath,
					shouldOpen = state.openXcodeAfterGenerate
				] send in
					do {
						let projectPath = try await XcodeProjectGenerator.generateProject(
							at: path,
							iosSubfolderPath: iosSubfolderPath,
							shouldOpenXcode: shouldOpen
						) { newState in
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
				state.alert = .okAlert(
					title: "Project Generation Failed",
					message: error
				)
				return .none

			case .alert:
				// When alert is dismissed, reset state
				state.projectState = .idle
				return .none
			}
		}
		.ifLet(\.$alert, action: \.alert)
	}
}
