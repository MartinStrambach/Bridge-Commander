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
		/// The tool whose manifest the iOS subfolder holds, which the button runs when the project
		/// is missing. Nil when there is none, and then a missing project cannot be made here.
		var generator: ProjectGenerator?
		var iosSubfolderPath: String
		var xcodeFilePreference: XcodeFilePreference
		@Shared(.openXcodeAfterGenerate)
		var openXcodeAfterGenerate = true
		@Shared(.misePath)
		var misePath = NSHomeDirectory() + "/.local/bin/mise"
		@Shared(.tuistRunMode)
		var tuistRunMode = GeneratorRunMode.mise
		@Shared(.xcodeGenRunMode)
		var xcodeGenRunMode = GeneratorRunMode.mise
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
		case foundProjectPath(String?, generator: ProjectGenerator?)
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

			case let .foundProjectPath(path, generator: generator):
				state.projectState = .idle
				state.projectPath = path
				state.generator = generator
				state.isLoaded = true
				return .none

			case .openProject:
				guard let projectPath = state.projectPath else {
					guard let generator = state.generator else {
						return .none
					}
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
						TextState("No Xcode project or workspace was found.\n\nWould you like to generate one with \(generator.displayName)?")
					}
					return .none
				}

				state.projectState = .opening

				return .run { send in
					do {
						try await xcodeClient.openProject(at: projectPath)
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
				guard let generator = state.generator else {
					return .none
				}

				return .run { [
					path = state.repositoryPath,
					iosSubfolderPath = state.iosSubfolderPath,
					shouldOpen = state.openXcodeAfterGenerate,
					misePath = state.misePath,
					runMode = generator == .tuist ? state.tuistRunMode : state.xcodeGenRunMode
				] send in
					do {
						// Progress is awaited, not sent from a detached `Task`: unordered, the last
						// `.checking` could land after `didOpenProject` and leave the button spinning.
						let projectPath = try await xcodeClient.generateProject(
							at: path,
							iosSubfolderPath: iosSubfolderPath,
							generator: generator,
							shouldOpenXcode: shouldOpen,
							misePath: misePath,
							runMode: runMode
						) { newState in
							await send(.projectGenerationProgress(newState))
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
			let generator = xcodeClient.projectGenerator(in: path, iosSubfolderPath: iosSubfolderPath)
			await send(.foundProjectPath(projectPath, generator: generator))
		}
	}
}
