import AppUI
import ComposableArchitecture
import Foundation
import Settings
import ToolsIntegration

// MARK: - Xcode Project Button Reducer

@Reducer
struct XcodeProjectButtonReducer {
	@ObservableState
	struct State: Equatable {
		let repositoryPath: String
		var projectState: XcodeProjectState = .idle
		var projectPath: String?
		var usesTuist: Bool = false
		var iosSubfolderPath: String
		var xcodeFilePreference: XcodeFilePreference
		@Shared(.openXcodeAfterGenerate)
		var openXcodeAfterGenerate = true
		@Shared(.misePath)
		var misePath = NSHomeDirectory() + "/.local/bin/mise"
		@Shared(.tuistRunMode)
		var tuistRunMode = TuistRunMode.mise
		@Presents
		var alert: AlertState<Action.Alert>?
		@Presents
		var errorAlert: ScrollableAlertReducer.State?

		fileprivate var isLoaded = false

		init(repositoryPath: String, iosSubfolderPath: String, xcodeFilePreference: XcodeFilePreference = .auto) {
			self.repositoryPath = repositoryPath
			self.iosSubfolderPath = iosSubfolderPath
			self.xcodeFilePreference = xcodeFilePreference
		}
	}

	enum Action {
		case onAppear
		case refresh
		case foundProjectPath(String?, usesTuist: Bool)
		case openProject
		case didOpenProject
		case openFailed(String)
		case projectGenerationProgress(XcodeProjectState)
		case didGenerateProject(String)
		case generationFailed(String)
		case alert(PresentationAction<Alert>)
		case errorAlert(PresentationAction<ScrollableAlertReducer.Action>)

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
				guard !state.isLoaded else {
					return .none
				}

				return findProjectEffect(state: &state)

			case .refresh:
				return findProjectEffect(state: &state)

			case let .foundProjectPath(path, usesTuist: usesTuist):
				state.projectState = .idle
				state.projectPath = path
				state.usesTuist = usesTuist
				state.isLoaded = true
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
				state.errorAlert = .init(
					title: "Failed to Open Xcode Project",
					message: error,
					isError: true
				)
				return .none

			case .alert(.presented(.confirmGenerate)):
				return .run { [
					path = state.repositoryPath,
					iosSubfolderPath = state.iosSubfolderPath,
					shouldOpen = state.openXcodeAfterGenerate,
					misePath = state.misePath,
					runMode = state.tuistRunMode
				] send in
					do {
						let projectPath = try await XcodeProjectGenerator.generateProject(
							at: path,
							iosSubfolderPath: iosSubfolderPath,
							shouldOpenXcode: shouldOpen,
							misePath: misePath,
							runMode: runMode
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
				state.errorAlert = .init(
					title: "Project Generation Failed",
					message: error,
					isError: true
				)
				return .none

			case .alert:
				// When alert is dismissed, reset state
				state.projectState = .idle
				return .none

			case .errorAlert:
				state.projectState = .idle
				return .none
			}
		}
		.ifLet(\.$alert, action: \.alert)
		.ifLet(\.$errorAlert, action: \.errorAlert) {
			ScrollableAlertReducer()
		}
	}

	private func findProjectEffect(state: inout State) -> EffectOf<XcodeProjectButtonReducer> {
		guard !state.projectState.isProcessing else {
			return .none
		}

		return .run { [path = state.repositoryPath, iosSubfolderPath = state.iosSubfolderPath, preference = state.xcodeFilePreference] send in
			let projectPath = xcodeClient.findXcodeProject(in: path, iosSubfolderPath: iosSubfolderPath, preference: preference)
			let usesTuist = XcodeProjectDetector.hasTuistManifest(in: path, iosSubfolderPath: iosSubfolderPath)
			await send(.foundProjectPath(projectPath, usesTuist: usesTuist))
		}
	}
}
