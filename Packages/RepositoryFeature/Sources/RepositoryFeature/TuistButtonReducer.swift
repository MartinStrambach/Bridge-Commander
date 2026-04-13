import ComposableArchitecture
import Foundation
import AppUI
import Settings
import ToolsIntegration

// MARK: - Tuist Button Reducer

@Reducer
struct TuistButtonReducer {
	@ObservableState
	struct State: Equatable {
		let repositoryPath: String
		var runningAction: TuistAction?
		var iosSubfolderPath: String
		@Shared(.openXcodeAfterGenerate)
		var openXcodeAfterGenerate = true
		@Shared(.tuistCacheType)
		var tuistCacheType = TuistCacheType.externalOnly
		@Shared(.misePath)
		var misePath = NSHomeDirectory() + "/.local/bin/mise"
		@Shared(.tuistRunMode)
		var tuistRunMode = TuistRunMode.mise
		@Presents
		var alert: ScrollableAlertReducer.State?

		var isProcessing: Bool {
			runningAction != nil
		}

		init(repositoryPath: String, iosSubfolderPath: String) {
			self.repositoryPath = repositoryPath
			self.iosSubfolderPath = iosSubfolderPath
			self.runningAction = nil
		}
	}

	enum Action {
		case generateTapped
		case installTapped
		case installUpdateTapped
		case cacheTapped
		case editTapped
		case inspectDependenciesTapped
		case actionCompleted(TuistAction, Result<String, Error>)
		case alert(PresentationAction<ScrollableAlertReducer.Action>)
	}

	var body: some Reducer<State, Action> {
		Reduce { state, action in
			switch action {
			case .generateTapped:
				guard state.runningAction == nil else {
					return .none
				}

				state.runningAction = .generate
				return .run { [
					repositoryPath = state.repositoryPath,
					iosSubfolderPath = state.iosSubfolderPath,
					shouldOpen = state.openXcodeAfterGenerate,
					misePath = state.misePath,
					runMode = state.tuistRunMode
				] send in
					let iosFlashscorePath = XcodeProjectDetector.getIosFlashscorePath(
						in: repositoryPath,
						iosSubfolderPath: iosSubfolderPath
					)
					let result = await TuistCommandHelper.runCommand(
						.generate,
						at: iosFlashscorePath,
						shouldOpenXcode: shouldOpen,
						misePath: misePath,
						runMode: runMode
					)
					await send(.actionCompleted(.generate, result))
				}

			case .installTapped:
				guard state.runningAction == nil else {
					return .none
				}

				state.runningAction = .install
				return .run { [
					repositoryPath = state.repositoryPath,
					iosSubfolderPath = state.iosSubfolderPath,
					shouldOpen = state.openXcodeAfterGenerate,
					misePath = state.misePath,
					runMode = state.tuistRunMode
				] send in
					let iosFlashscorePath = XcodeProjectDetector.getIosFlashscorePath(
						in: repositoryPath,
						iosSubfolderPath: iosSubfolderPath
					)
					let result = await TuistCommandHelper.runCommand(
						.install,
						at: iosFlashscorePath,
						shouldOpenXcode: shouldOpen,
						misePath: misePath,
						runMode: runMode
					)
					await send(.actionCompleted(.install, result))
				}

			case .installUpdateTapped:
				guard state.runningAction == nil else {
					return .none
				}

				state.runningAction = .installUpdate
				return .run { [
					repositoryPath = state.repositoryPath,
					iosSubfolderPath = state.iosSubfolderPath,
					shouldOpen = state.openXcodeAfterGenerate,
					misePath = state.misePath,
					runMode = state.tuistRunMode
				] send in
					let iosFlashscorePath = XcodeProjectDetector.getIosFlashscorePath(
						in: repositoryPath,
						iosSubfolderPath: iosSubfolderPath
					)
					let result = await TuistCommandHelper.runCommand(
						.installUpdate,
						at: iosFlashscorePath,
						shouldOpenXcode: shouldOpen,
						misePath: misePath,
						runMode: runMode
					)
					await send(.actionCompleted(.installUpdate, result))
				}

			case .cacheTapped:
				guard state.runningAction == nil else {
					return .none
				}

				let cacheType = state.tuistCacheType
				state.runningAction = .cache(cacheType)
				return .run { [
					repositoryPath = state.repositoryPath,
					iosSubfolderPath = state.iosSubfolderPath,
					shouldOpen = state.openXcodeAfterGenerate,
					cacheType,
					misePath = state.misePath,
					runMode = state.tuistRunMode
				] send in
					let iosFlashscorePath = XcodeProjectDetector.getIosFlashscorePath(
						in: repositoryPath,
						iosSubfolderPath: iosSubfolderPath
					)
					let result = await TuistCommandHelper.runCommand(
						.cache(cacheType),
						at: iosFlashscorePath,
						shouldOpenXcode: shouldOpen,
						misePath: misePath,
						runMode: runMode
					)
					await send(.actionCompleted(.cache(cacheType), result))
				}

			case .editTapped:
				guard state.runningAction == nil else {
					return .none
				}

				state.runningAction = .edit
				return .run { [
					repositoryPath = state.repositoryPath,
					iosSubfolderPath = state.iosSubfolderPath,
					misePath = state.misePath,
					runMode = state.tuistRunMode
				] send in
					let iosFlashscorePath = XcodeProjectDetector.getIosFlashscorePath(
						in: repositoryPath,
						iosSubfolderPath: iosSubfolderPath
					)
					let result = await TuistCommandHelper.runCommand(
						.edit,
						at: iosFlashscorePath,
						shouldOpenXcode: false,
						misePath: misePath,
						runMode: runMode
					)
					await send(.actionCompleted(.edit, result))
				}

			case .inspectDependenciesTapped:
				guard state.runningAction == nil else {
					return .none
				}

				state.runningAction = .inspectDependencies
				return .run { [
					repositoryPath = state.repositoryPath,
					iosSubfolderPath = state.iosSubfolderPath,
					misePath = state.misePath,
					runMode = state.tuistRunMode
				] send in
					let iosFlashscorePath = XcodeProjectDetector.getIosFlashscorePath(
						in: repositoryPath,
						iosSubfolderPath: iosSubfolderPath
					)
					let result = await TuistCommandHelper.runCommand(
						.inspectDependencies,
						at: iosFlashscorePath,
						shouldOpenXcode: false,
						misePath: misePath,
						runMode: runMode
					)
					await send(.actionCompleted(.inspectDependencies, result))
				}

			case let .actionCompleted(tuistAction, result):
				state.runningAction = nil
				switch result {
				case let .success(output):
					if tuistAction == .inspectDependencies {
						state.alert = .init(
							title: "Implicit Dependencies",
							message: output.isEmpty ? "No implicit dependencies found." : output,
							isError: false
						)
					}
					return .none

				case let .failure(error):
					let title =
						switch tuistAction {
						case .generate: "Tuist Generate Failed"
						case .install: "Tuist Install Failed"
						case .installUpdate: "Tuist Install Failed"
						case .cache: "Tuist Cache Failed"
						case .edit: "Tuist Edit Failed"
						case .inspectDependencies: "Tuist Inspect Failed"
						}
					state.alert = .init(
						title: title,
						message: error.localizedDescription,
						isError: true
					)
					return .none
				}

			case .alert:
				return .none
			}
		}
		.ifLet(\.$alert, action: \.alert) {
			ScrollableAlertReducer()
		}
	}
}
