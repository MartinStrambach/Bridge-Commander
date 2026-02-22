import ComposableArchitecture
import Foundation

// MARK: - Tuist Button Reducer

@Reducer
struct TuistButtonReducer {
	@ObservableState
	struct State: Equatable {
		let repositoryPath: String
		var runningAction: TuistAction?
		@Shared(.iosSubfolderPath)
		var iosSubfolderPath = "ios/FlashScore"
		@Shared(.openXcodeAfterGenerate)
		var openXcodeAfterGenerate = true
		@Shared(.tuistCacheType)
		var tuistCacheType = TuistCacheType.externalOnly
		@Presents
		var alert: GitAlertReducer.State?

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
		case alert(PresentationAction<GitAlertReducer.Action>)
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

				let cacheType = state.tuistCacheType
				state.runningAction = .cache(cacheType)
				return .run { [
					repositoryPath = state.repositoryPath,
					iosSubfolderPath = state.iosSubfolderPath,
					shouldOpen = state.openXcodeAfterGenerate,
					cacheType
				] send in
					let iosFlashscorePath = XcodeProjectDetector.getIosFlashscorePath(
						in: repositoryPath,
						iosSubfolderPath: iosSubfolderPath
					)
					let result = await TuistCommandHelper.runCommand(
						.cache(cacheType),
						at: iosFlashscorePath,
						shouldOpenXcode: shouldOpen
					)
					await send(.actionCompleted(.cache(cacheType), result))
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
			GitAlertReducer()
		}
	}
}
