import ComposableArchitecture
import Foundation
import GitCore
import ToolsIntegration

@Reducer
struct FileChangeList {
	enum ListType: Equatable {
		case staged
		case unstaged
	}

	@ObservableState
	struct State: Equatable {
		let repositoryPath: String
		let iosSubfolderPath: String
		let listType: ListType
		var files: [FileChange] = []
		var selectedFileIds: Set<String> = []
		var isLoading = true

		@Presents
		var alert: AlertState<Action.Alert>?

		init(repositoryPath: String, iosSubfolderPath: String, listType: ListType) {
			self.repositoryPath = repositoryPath
			self.iosSubfolderPath = iosSubfolderPath
			self.listType = listType
		}
	}

	enum Action {
		case updateSelection(Set<String>)
		case toggleSelectedTapped
		case toggleAllTapped
		case spaceKeyPressed
		case openInIDE(FileChange)
		case openInIDEFailed(String)
		case alert(PresentationAction<Alert>)
		case delegate(Delegate)

		enum Alert: Equatable {}

		enum Delegate {
			case toggleAll([FileChange])
			case discardChanges([FileChange])
			case deleteUntracked([FileChange])
			case deleteConflicted([FileChange])
		}
	}

	var body: some Reducer<State, Action> {
		Reduce { state, action in
			switch action {
			case let .updateSelection(ids):
				state.selectedFileIds = ids
				return .none

			case .toggleSelectedTapped:
				let files = state.files.filter { state.selectedFileIds.contains($0.id) }
				return .send(.delegate(.toggleAll(files)))

			case .toggleAllTapped:
				return .send(.delegate(.toggleAll(state.files)))

			case .spaceKeyPressed:
				guard !state.selectedFileIds.isEmpty else {
					return .none
				}

				let files = state.files.filter { state.selectedFileIds.contains($0.id) }
				state.selectedFileIds.removeAll()
				return .send(.delegate(.toggleAll(files)))

			case let .openInIDE(file):
				return .run { [path = state.repositoryPath, iosSubfolderPath = state.iosSubfolderPath] send in
					do {
						let xcodeProjectPath = XcodeProjectDetector.findXcodeProject(
							in: path,
							iosSubfolderPath: iosSubfolderPath
						)
						try await FileOpener.openFileInIDE(
							filePath: file.path,
							repositoryPath: path,
							xcodeProjectPath: xcodeProjectPath
						)
					}
					catch {
						await send(.openInIDEFailed(error.localizedDescription))
					}
				}

			case let .openInIDEFailed(message):
				state.alert = .okAlert(title: "Failed to Open File", message: message)
				return .none

			case .alert:
				return .none

			case .delegate:
				return .none
			}
		}
		.ifLet(\.$alert, action: \.alert)
	}
}
