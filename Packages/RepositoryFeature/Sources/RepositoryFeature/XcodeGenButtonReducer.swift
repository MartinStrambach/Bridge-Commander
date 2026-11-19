import AppUI
import ComposableArchitecture
import Foundation
import Settings
import ToolsIntegration

// MARK: - XcodeGen Button Reducer

/// The XcodeGen menu: generate the Xcode project from the spec, open the spec, show its summary.
@Reducer
struct XcodeGenButtonReducer {
	@ObservableState
	struct State: Equatable {
		let repositoryPath: String
		var runningAction: XcodeGenAction?
		var iosSubfolderPath: String
		/// Which of a workspace and a project a Generate opens, as the group's Xcode button does.
		var xcodeFilePreference: XcodeFilePreference
		@Shared(.openXcodeAfterGenerate)
		var openXcodeAfterGenerate = true
		@Shared(.misePath)
		var misePath = NSHomeDirectory() + "/.local/bin/mise"
		@Shared(.xcodeGenRunMode)
		var xcodeGenRunMode = GeneratorRunMode.mise
		@Presents
		var alert: ScrollableAlertReducer.State?

		init(repositoryPath: String, iosSubfolderPath: String, xcodeFilePreference: XcodeFilePreference = .auto) {
			self.repositoryPath = repositoryPath
			self.iosSubfolderPath = iosSubfolderPath
			self.xcodeFilePreference = xcodeFilePreference
		}
	}

	enum Action {
		case generateTapped
		case generateUsingCacheTapped
		case dumpSummaryTapped
		case editSpecTapped
		case actionCompleted(XcodeGenAction, Result<String, Error>)
		case editSpecFailed(String)
		case alert(PresentationAction<ScrollableAlertReducer.Action>)
	}

	@Dependency(XcodeGenClient.self)
	private var xcodeGenClient

	@Dependency(XcodeClient.self)
	private var xcodeClient

	var body: some Reducer<State, Action> {
		Reduce { state, action in
			switch action {
			case .generateTapped:
				return run(.generate, state: &state)

			case .generateUsingCacheTapped:
				return run(.generateUsingCache, state: &state)

			case .dumpSummaryTapped:
				return run(.dumpSummary, state: &state)

			case .editSpecTapped:
				return .run { [repositoryPath = state.repositoryPath, iosSubfolderPath = state.iosSubfolderPath] send in
					do {
						try await xcodeGenClient.openSpec(repositoryPath: repositoryPath, iosSubfolderPath: iosSubfolderPath)
					}
					catch {
						await send(.editSpecFailed(error.localizedDescription))
					}
				}

			case let .actionCompleted(xcodeGenAction, result):
				state.runningAction = nil
				switch result {
				case let .success(output):
					if xcodeGenAction == .dumpSummary {
						state.alert = .init(
							title: "XcodeGen Spec Summary",
							message: output.isEmpty ? "XcodeGen printed no summary." : output,
							isError: false
						)
					}
					return .none

				case let .failure(error):
					let title =
						switch xcodeGenAction {
						case .generate, .generateUsingCache: "XcodeGen Generate Failed"
						case .dumpSummary: "XcodeGen Dump Failed"
						}
					state.alert = .init(title: title, message: error.localizedDescription, isError: true)
					return .none
				}

			case let .editSpecFailed(message):
				state.alert = .init(title: "Could Not Open the XcodeGen Spec", message: message, isError: true)
				return .none

			case .alert:
				return .none
			}
		}
		.ifLet(\.$alert, action: \.alert) {
			ScrollableAlertReducer()
		}
	}

	/// Runs `action` in the Xcode project path unless a command is already running. XcodeGen never
	/// opens Xcode itself, so after a generate the project is opened here when the setting asks.
	private func run(_ action: XcodeGenAction, state: inout State) -> Effect<Action> {
		guard state.runningAction == nil else {
			return .none
		}

		state.runningAction = action
		return .run { [
			repositoryPath = state.repositoryPath,
			iosSubfolderPath = state.iosSubfolderPath,
			shouldOpen = state.openXcodeAfterGenerate,
			preference = state.xcodeFilePreference,
			misePath = state.misePath,
			runMode = state.xcodeGenRunMode
		] send in
			let iosFolderPath = XcodeProjectDetector.iosFolderPath(in: repositoryPath, iosSubfolderPath: iosSubfolderPath)
			var result = await xcodeGenClient.run(action: action, at: iosFolderPath, misePath: misePath, runMode: runMode)

			if case .success = result, action.generatesProject, shouldOpen {
				if
					let projectPath = xcodeClient.findXcodeProject(
						in: repositoryPath,
						iosSubfolderPath: iosSubfolderPath,
						preference: preference
					)
				{
					do {
						try await xcodeClient.openProject(at: projectPath)
					}
					catch {
						result = .failure(OpenAfterGenerateError(underlying: error.localizedDescription))
					}
				}
				else {
					result = .failure(OpenAfterGenerateError(underlying: "No Xcode project was found after generating."))
				}
			}

			await send(.actionCompleted(action, result))
		}
	}
}

/// The project was generated, but opening it in Xcode afterwards failed.
private struct OpenAfterGenerateError: LocalizedError {
	let underlying: String

	var errorDescription: String? {
		"The project was generated, but could not be opened in Xcode: \(underlying)"
	}
}
