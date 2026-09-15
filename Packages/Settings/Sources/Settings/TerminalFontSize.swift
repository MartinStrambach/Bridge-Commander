import Foundation

/// The point size of the built-in terminal's font.
///
/// A bare `Double` in user defaults rather than a case list: font size is a continuous preference,
/// and the stepper and the ⌘+/⌘− shortcuts add and subtract points rather than walk named cases.
public enum TerminalFontSize {

	/// `NSFont.systemFontSize` (13 pt), which is the size SwiftTerm's own default font uses — so an
	/// install that never touches this setting renders exactly as it did before the setting existed.
	/// Spelled as a literal because a global initialized from `NSFont` would pull AppKit into the
	/// type for a value that has been 13 for the lifetime of the platform.
	public static let `default`: Double = 13

	/// Below ~8 pt the cell grid gets so fine that a pane is mostly unreadable; above ~32 pt a
	/// normal pane no longer fits the 80 columns most CLI output assumes.
	public static let minimum: Double = 8
	public static let maximum: Double = 32

	public static let step: Double = 1

	/// Keeps a value inside the supported range.
	///
	/// Clamping rather than rejecting: the value also arrives from user defaults, which anything can
	/// write, and SwiftTerm divides the pane width by the cell width to get its column count — a
	/// zero or negative size would make that division meaningless.
	public static func clamped(_ size: Double) -> Double {
		min(max(size, minimum), maximum)
	}

	/// The next size up, stopping at `maximum`.
	public static func zoomedIn(from size: Double) -> Double {
		clamped(size + step)
	}

	/// The next size down, stopping at `minimum`.
	public static func zoomedOut(from size: Double) -> Double {
		clamped(size - step)
	}
}
