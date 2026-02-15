import SwiftUI

extension View {
	/// Adds a handler for Return key press events
	/// - Parameter action: The action to perform when Return is pressed
	/// - Returns: A view that handles Return key presses
	func onReturnPress(_ action: @escaping () -> Void) -> some View {
		onKeyPress(.return) {
			action()
			return .handled
		}
	}
}
