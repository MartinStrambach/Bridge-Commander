import AppUI
import Foundation
import Sharing
import SwiftUI

/// The size of the app's own text (not the terminal's, see `TerminalFontSize`), as the point size
/// of body text. Every other text style scales by the same ratio, so the hierarchy between a
/// headline and a caption stays as macOS draws it.
///
/// A body size rather than a percentage because points are what the terminal's setting beside it
/// already speaks, and "13 pt" is a size people know from every other Mac app.
public enum UIFontSize {

	/// macOS's body size, so an install that never touches the setting is drawn at scale 1.
	public static let `default`: Double = 13

	/// Below 10 pt captions (drawn at 10/13 of body) fall under 8 pt; above 20 pt the repository
	/// rows' fixed-width columns run out of room.
	public static let minimum: Double = 10
	public static let maximum: Double = 20

	public static let step: Double = 1

	/// Keeps a value inside the supported range. Clamping rather than rejecting because the value
	/// also arrives from user defaults, which anything can write.
	public static func clamped(_ size: Double) -> Double {
		min(max(size, minimum), maximum)
	}

	/// The factor every text style is multiplied by.
	public static func scale(for size: Double) -> CGFloat {
		CGFloat(clamped(size) / `default`)
	}
}

private struct AppUIFontSize: ViewModifier {
	@Shared(.uiFontSize)
	private var uiFontSize = UIFontSize.default

	func body(content: Content) -> some View {
		content.uiFontScale(UIFontSize.scale(for: uiFontSize))
	}
}

public extension View {
	/// Draws the app's text at the size picked in Settings. Applied at the root of each scene.
	func appUIFontSize() -> some View {
		modifier(AppUIFontSize())
	}
}
