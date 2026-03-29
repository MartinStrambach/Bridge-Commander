import ComposableArchitecture
import Foundation
import Settings
import ToolsIntegration

// MARK: - Terminal Button Reducer

@Reducer
struct TerminalButtonReducer {
	@ObservableState
	struct State: Equatable {
		let repositoryPath: String

		@Shared(.terminalOpeningBehavior)
		var terminalOpeningBehavior = TerminalOpeningBehavior.newTab

		var mobileSubfolderPath: String

		init(repositoryPath: String, mobileSubfolderPath: String = "") {
			self.repositoryPath = repositoryPath
			self.mobileSubfolderPath = mobileSubfolderPath
		}
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
