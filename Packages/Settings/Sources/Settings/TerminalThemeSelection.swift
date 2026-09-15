import AppKit
import Foundation

/// Which color scheme the built-in terminal uses: one of the bundled themes, or a profile
/// imported from Terminal.app.
///
/// The raw value of a built-in case is the bare `TerminalColorTheme` raw value, unprefixed, so
/// the settings this type replaced (which stored exactly that) keep working — an existing
/// `"dracula"` in user defaults still reads back as `.builtIn(.dracula)`.
public enum TerminalThemeSelection: RawRepresentable, Equatable, Hashable, Sendable {
	case builtIn(TerminalColorTheme)
	case imported(name: String)

	private static let importedPrefix = "imported:"

	public init?(rawValue: String) {
		if rawValue.hasPrefix(Self.importedPrefix) {
			let name = String(rawValue.dropFirst(Self.importedPrefix.count))
			guard !name.isEmpty else { return nil }
			self = .imported(name: name)
			return
		}
		guard let theme = TerminalColorTheme(rawValue: rawValue) else { return nil }
		self = .builtIn(theme)
	}

	public var rawValue: String {
		switch self {
		case let .builtIn(theme): theme.rawValue
		case let .imported(name): Self.importedPrefix + name
		}
	}

	public var displayName: String {
		switch self {
		case let .builtIn(theme): theme.displayName
		case let .imported(name): name
		}
	}
}

/// The colors the terminal is actually configured with, once a selection has been looked up
/// against the imported profiles.
public struct ResolvedTerminalTheme: Equatable {
	public var foreground: NSColor
	public var background: NSColor
	/// The 16 ANSI colors, or `nil` to leave SwiftTerm's default palette in place.
	public var ansiPalette: [NSColor]?

	public init(foreground: NSColor, background: NSColor, ansiPalette: [NSColor]? = nil) {
		self.foreground = foreground
		self.background = background
		self.ansiPalette = ansiPalette
	}
}

public extension TerminalThemeSelection {
	/// Resolves to concrete colors.
	///
	/// A selection naming a profile that is no longer installed falls back to the default
	/// built-in theme, so deleting an imported profile cannot leave the terminal unreadable.
	func resolve(profiles: [TerminalProfile]) -> ResolvedTerminalTheme {
		switch self {
		case let .builtIn(theme):
			// The bundled themes define no ANSI palette, so SwiftTerm keeps its default one —
			// this is exactly how they rendered before profiles existed.
			return ResolvedTerminalTheme(
				foreground: theme.foregroundColor,
				background: theme.backgroundColor
			)

		case let .imported(name):
			guard let profile = profiles.first(where: { $0.name == name }) else {
				return TerminalThemeSelection.builtIn(.basicDark).resolve(profiles: profiles)
			}
			return ResolvedTerminalTheme(
				foreground: profile.foreground.nsColor,
				background: profile.background.nsColor,
				ansiPalette: profile.ansi?.map(\.nsColor)
			)
		}
	}
}
