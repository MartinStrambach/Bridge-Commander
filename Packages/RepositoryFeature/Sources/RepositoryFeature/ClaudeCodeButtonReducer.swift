import ComposableArchitecture
import Foundation
import Settings
import ToolsIntegration

@Reducer
struct ClaudeCodeButtonReducer {
	@ObservableState
	struct State: Equatable {
		let repositoryPath: String
		var isLaunching = false

		@Shared(.terminalApp)
		var terminalApp = TerminalApp.systemTerminal

		@Shared(.claudeCodeOpeningBehavior)
		var claudeCodeOpeningBehavior = TerminalOpeningBehavior.newWindow

		var mobileSubfolderPath: String

		@Presents
		var alert: AlertState<Action.Alert>?

		init(repositoryPath: String, mobileSubfolderPath: String = "") {
			self.repositoryPath = repositoryPath
			self.mobileSubfolderPath = mobileSubfolderPath
		}
	}

	enum Action: Equatable {
		case launchClaudeCodeButtonTapped
		case didLaunchClaudeCode
		case launchFailed(String)
		case alert(PresentationAction<Alert>)

		enum Alert: Equatable {}
	}

	var body: some Reducer<State, Action> {
		Reduce { state, action in
			switch action {
			case .launchClaudeCodeButtonTapped:
				state.isLaunching = true
				return .run { [
					path = state.repositoryPath,
					subfolder = state.mobileSubfolderPath.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
					app = state.terminalApp,
					behavior = state.claudeCodeOpeningBehavior
				] send in
					let targetPath = (path as NSString).appendingPathComponent(subfolder)
					do {
						try await TerminalLauncher.openTerminal(
							at: targetPath,
							app: app,
							behavior: behavior,
							command: "claude"
						)
						await send(.didLaunchClaudeCode)
					}
					catch {
						await send(.launchFailed(error.localizedDescription))
					}
				}

			case .didLaunchClaudeCode:
				state.isLaunching = false
				return .none

			case let .launchFailed(errorMessage):
				state.isLaunching = false
				state.alert = .okAlert(
					title: "Failed to Launch Claude Code",
					message: errorMessage
				)
				return .none

			case .alert:
				return .none
			}
		}
		.ifLet(\.$alert, action: \.alert)
	}
}
