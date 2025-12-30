import ComposableArchitecture
import Foundation

// MARK: - Tuist Button Reducer

@Reducer
struct TuistButtonReducer {
	@ObservableState
	struct State: Equatable {
		let repositoryPath: String
		var runningAction: TuistAction?
		@Shared(.appStorage("iosSubfolderPath"))
		var iosSubfolderPath = "ios/FlashScore"
		@Shared(.appStorage("openXcodeAfterGenerate"))
		var openXcodeAfterGenerate = true
		@Presents
		var alert: AlertState<Action.Alert>?

		var isProcessing: Bool {
			runningAction != nil
		}
	}

	enum Action {
		case generateTapped
		case installTapped
		case cacheTapped
		case editTapped
		case actionCompleted(TuistAction, Result<String, Error>)
		case alert(PresentationAction<Alert>)

		enum Alert: Equatable {
			case dismissError
		}
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
					shouldOpen = state.openXcodeAfterGenerate
				] send in
					let iosFlashscorePath = XcodeProjectDetector.getIosFlashscorePath(
						in: repositoryPath,
						iosSubfolderPath: iosSubfolderPath
					)
					let result = await TuistCommandHelper.runCommand(
						.generate,
						at: iosFlashscorePath,
						shouldOpenXcode: shouldOpen
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
					shouldOpen = state.openXcodeAfterGenerate
				] send in
					let iosFlashscorePath = XcodeProjectDetector.getIosFlashscorePath(
						in: repositoryPath,
						iosSubfolderPath: iosSubfolderPath
					)
					let result = await TuistCommandHelper.runCommand(
						.install,
						at: iosFlashscorePath,
						shouldOpenXcode: shouldOpen
					)
					await send(.actionCompleted(.install, result))
				}

			case .cacheTapped:
				guard state.runningAction == nil else {
					return .none
				}

				state.runningAction = .cache
				return .run { [
					repositoryPath = state.repositoryPath,
					iosSubfolderPath = state.iosSubfolderPath,
					shouldOpen = state.openXcodeAfterGenerate
				] send in
					let iosFlashscorePath = XcodeProjectDetector.getIosFlashscorePath(
						in: repositoryPath,
						iosSubfolderPath: iosSubfolderPath
					)
					let result = await TuistCommandHelper.runCommand(
						.cache,
						at: iosFlashscorePath,
						shouldOpenXcode: shouldOpen
					)
					await send(.actionCompleted(.cache, result))
				}

			case .editTapped:
				guard state.runningAction == nil else {
					return .none
				}

				state.runningAction = .edit
				return .run { [repositoryPath = state.repositoryPath, iosSubfolderPath = state.iosSubfolderPath] send in
					let iosFlashscorePath = XcodeProjectDetector.getIosFlashscorePath(
						in: repositoryPath,
						iosSubfolderPath: iosSubfolderPath
					)
					let result = await TuistCommandHelper.runCommand(
						.edit,
						at: iosFlashscorePath,
						shouldOpenXcode: false
					)
					await send(.actionCompleted(.edit, result))
				}

			case let .actionCompleted(tuistAction, result):
				state.runningAction = nil
				switch result {
				case .success:
					return .none
				case let .failure(error):
					let title =
						switch tuistAction {
						case .generate: "Tuist Generate Failed"
						case .install: "Tuist Install Failed"
						case .cache: "Tuist Cache Failed"
						case .edit: "Tuist Edit Failed"
						}
					state.alert = AlertState {
						TextState(title)
					} actions: {
						ButtonState(role: .cancel, action: .dismissError) {
							TextState("OK")
						}
					} message: {
						TextState(error.localizedDescription)
					}
					return .none
				}

			case .alert:
				return .none
			}
		}
		.ifLet(\.$alert, action: \.alert)
	}
}
