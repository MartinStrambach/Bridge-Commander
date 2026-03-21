import ComposableArchitecture
import Foundation

// MARK: - Terminal Button Reducer

@Reducer
struct TerminalButtonReducer {
	@ObservableState
	struct State: Equatable {
		let repositoryPath: String

		@Shared(.terminalOpeningBehavior)
		var terminalOpeningBehavior = TerminalOpeningBehavior.newTab

		@Shared(.mobileSubfolderPath)
		var mobileSubfolderPath = ""
	}

	enum Action: Equatable {
		case openTerminalButtonTapped
	}

	var body: some Reducer<State, Action> {
		Reduce { state, action in
			switch action {
			case .openTerminalButtonTapped:
				.run { [
					path = state.repositoryPath,
					subfolder = state.mobileSubfolderPath.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
					behavior = state.terminalOpeningBehavior
				] _ in
					let targetPath = (path as NSString).appendingPathComponent(subfolder)
					await TerminalLauncher.openTerminal(at: targetPath, behavior: behavior)
				}
			}
		}
	}
}
