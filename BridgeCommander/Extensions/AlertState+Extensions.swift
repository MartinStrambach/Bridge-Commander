import ComposableArchitecture
import Foundation

extension AlertState {
	/// Creates a simple alert with a title, message, and OK button
	static func okAlert(title: String, message: String) -> Self {
		AlertState {
			TextState(title)
		} actions: {
			ButtonState(role: .cancel) {
				TextState("OK")
			}
		} message: {
			TextState(message)
		}
	}
}
