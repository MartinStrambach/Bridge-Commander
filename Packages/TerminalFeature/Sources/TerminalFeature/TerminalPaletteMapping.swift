import AppKit
import Foundation
import SwiftTerm

/// Converts an AppKit palette into the color type SwiftTerm installs.
///
/// The palette crosses the package boundary as `[NSColor]` rather than as a Settings type, so
/// TerminalFeature stays free of any dependency on Settings — the same split the foreground and
/// background colors already use.
enum TerminalPaletteMapping {
	/// Converts 16 colors for `installColors`, or returns `nil` if the palette cannot be used.
	///
	/// SwiftTerm's `installColors` silently does nothing unless it gets exactly 16 colors, so a
	/// palette of any other length is rejected here instead of failing invisibly one layer down.
	static func swiftTermColors(from palette: [NSColor]) -> [SwiftTerm.Color]? {
		guard palette.count == 16 else { return nil }
		let converted = palette.compactMap(swiftTermColor(from:))
		return converted.count == palette.count ? converted : nil
	}

	static func swiftTermColor(from color: NSColor) -> SwiftTerm.Color? {
		// Any color space is possible here; converting first also avoids reading `redComponent`
		// off a grayscale color, which raises.
		guard let srgb = color.usingColorSpace(.sRGB) else { return nil }
		return SwiftTerm.Color(
			red8: UInt16((srgb.redComponent * 255).rounded()),
			green8: UInt16((srgb.greenComponent * 255).rounded()),
			blue8: UInt16((srgb.blueComponent * 255).rounded())
		)
	}
}
