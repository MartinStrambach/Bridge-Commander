import AppKit
import Foundation
import SwiftTerm

/// The colors a pane is created with, already resolved from the theme by the caller — as
/// `NSColor`, not a Settings type, so this package stays free of a Settings dependency.
public struct TerminalColors: Equatable {
	public var foreground: NSColor
	public var background: NSColor
	/// The 16 ANSI colors to install, or `nil` to keep SwiftTerm's default palette — which is
	/// Terminal.app's own, so an imported profile that defines no ANSI colors renders the same way
	/// Terminal renders it.
	public var ansiPalette: [NSColor]?
	/// The caret color, or `nil` to keep SwiftTerm's default. Most Terminal profiles set no cursor
	/// color, so `nil` is the usual case.
	public var cursor: NSColor?
	/// The selection background, or `nil` to keep SwiftTerm's default.
	public var selection: NSColor?

	public init(
		foreground: NSColor,
		background: NSColor,
		ansiPalette: [NSColor]? = nil,
		cursor: NSColor? = nil,
		selection: NSColor? = nil
	) {
		self.foreground = foreground
		self.background = background
		self.ansiPalette = ansiPalette
		self.cursor = cursor
		self.selection = selection
	}
}

extension ClaudeAwareTerminalView {
	/// Installs a pane's colors. Done once, as the pane is created: a new theme applies to newly
	/// opened terminals.
	func apply(_ colors: TerminalColors) {
		nativeForegroundColor = colors.foreground
		nativeBackgroundColor = colors.background
		// Installed after the fg/bg assignment: SwiftTerm derives the extended 256-color
		// palette from the 16 ANSI colors plus the terminal's own background and foreground.
		if let ansiPalette = colors.ansiPalette, let palette = TerminalPaletteMapping.swiftTermColors(from: ansiPalette) {
			installColors(palette)
		}
		if let cursor = colors.cursor {
			caretColor = cursor
		}
		if let selection = colors.selection {
			selectedTextBackgroundColor = selection
			// Not optional to set alongside it: SwiftTerm *replaces* the foreground of every
			// selected cell with `selectedTextForegroundColor`, which defaults to black — fine
			// against its own teal default, unreadable against the dark selection colors most
			// Terminal profiles ship. The theme's own text color is the right stand-in: the
			// profile's author picked a selection color that works behind exactly that text.
			selectedTextForegroundColor = colors.foreground
		}
	}
}
