import AppKit
import ComposableArchitecture
import Foundation

@Reducer
struct WebButtonReducer {
	@ObservableState
	struct State: Equatable {
		var repositoryPath: String
		var webIndexPath: String
	}

	enum Action: Equatable {
		case openWebButtonTapped
	}

	var body: some Reducer<State, Action> {
		Reduce { state, action in
			switch action {
			case .openWebButtonTapped:
				guard
					let url = Self.makeFileURL(
						repositoryPath: state.repositoryPath,
						webIndexPath: state.webIndexPath
					)
				else {
					return .none
				}

				NSWorkspace.shared.open(url)
				return .none
			}
		}
	}

	static func makeFileURL(repositoryPath: String, webIndexPath: String) -> URL? {
		let trimmed = webIndexPath.trimmingCharacters(in: .whitespaces)
		guard !trimmed.isEmpty else {
			return nil
		}

		if trimmed.hasPrefix("/") {
			return URL(fileURLWithPath: trimmed)
		}
		let relative = trimmed.hasPrefix("./") ? String(trimmed.dropFirst(2)) : trimmed
		let fullPath = (repositoryPath as NSString).appendingPathComponent(relative)
		return URL(fileURLWithPath: fullPath)
	}
}
