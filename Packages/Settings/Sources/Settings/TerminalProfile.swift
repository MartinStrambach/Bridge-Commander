import AppKit
import Foundation

/// A single color of an imported terminal profile, as opaque sRGB components in `0...1`.
///
/// Profiles are persisted as JSON, so a color cannot be stored as `NSColor`. Everything is
/// normalized to sRGB at import because that is the only form the terminal can consume, and
/// because Terminal.app stores colors in whatever space the color picker produced — Generic
/// RGB and Generic Gray both occur in Apple's own bundled profiles, and reading `redComponent`
/// off a gray color raises. Alpha is dropped: Terminal's "Clear" profiles are translucent
/// (0.85–0.95), the built-in terminal is not, and SwiftTerm's color type has no alpha channel.
public struct TerminalRGB: Codable, Equatable, Hashable, Sendable {
	public var red: Double
	public var green: Double
	public var blue: Double

	public init(red: Double, green: Double, blue: Double) {
		self.red = red.clampedToUnitRange
		self.green = green.clampedToUnitRange
		self.blue = blue.clampedToUnitRange
	}

	/// Converts an `NSColor` of any color space into sRGB components.
	/// Returns `nil` when the color cannot be represented in sRGB (e.g. a pattern color).
	public init?(_ nsColor: NSColor) {
		guard let srgb = nsColor.usingColorSpace(.sRGB) else { return nil }
		self.init(
			red: Double(srgb.redComponent),
			green: Double(srgb.greenComponent),
			blue: Double(srgb.blueComponent)
		)
	}

	public var nsColor: NSColor {
		NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
	}
}

private extension Double {
	/// Guards against out-of-range components in hand-edited or corrupt JSON.
	var clampedToUnitRange: Double {
		guard isFinite else { return 0 }
		return Swift.min(Swift.max(self, 0), 1)
	}
}

/// The typeface a Terminal.app profile was saved with.
///
/// Name and size always arrive together: Terminal stores this as a single archived `NSFont`, so
/// there is no profile that names a face without a size.
public struct TerminalProfileFont: Codable, Equatable, Hashable, Sendable {
	/// The PostScript name `NSFont(name:size:)` takes — what the archive's `NSName` holds, e.g.
	/// `SFMonoTerminal-Regular`.
	public var name: String
	/// Clamped to the range the font-size setting supports, since selecting the profile writes
	/// straight into it and Terminal allows sizes this app does not.
	public var size: Double

	public init(name: String, size: Double) {
		self.name = name
		self.size = TerminalFontSize.clamped(size)
	}

	/// Whether the named face is installed, and so can actually be applied.
	///
	/// Worth checking at every use rather than once at import: fonts come and go, and Terminal's
	/// own profiles name faces that ship *inside* Terminal.app and are not registered
	/// system-wide, so "not installed" is the common case rather than the exotic one.
	public var isAvailable: Bool {
		!name.isEmpty && NSFont(name: name, size: size) != nil
	}
}

/// A terminal color scheme imported from a Terminal.app profile.
///
/// `ansi` is optional on purpose rather than defaulted at import: several of Apple's bundled
/// profiles ("Basic", "Pro") define no ANSI colors at all and inherit Terminal's default
/// palette. Keeping the absence explicit lets the terminal fall back to SwiftTerm's built-in
/// `Color.terminalAppColors` — which *is* that default palette — instead of this layer
/// duplicating all sixteen values.
public struct TerminalProfile: Codable, Equatable, Hashable, Sendable, Identifiable {
	/// The 16 ANSI slots a complete palette must fill, in SwiftTerm's order.
	public static let ansiColorCount = 16

	public var name: String
	public var foreground: TerminalRGB
	public var background: TerminalRGB
	public var cursor: TerminalRGB?
	public var selection: TerminalRGB?
	/// Exactly ``ansiColorCount`` colors, or `nil` when the profile defined none.
	public private(set) var ansi: [TerminalRGB]?
	/// The profile's typeface, or `nil` when it defined none.
	public var font: TerminalProfileFont?

	/// The profile name doubles as its identity: Terminal.app keys its own profiles by name,
	/// so re-importing an edited profile should replace the old one rather than duplicate it.
	public var id: String { name }

	public init(
		name: String,
		foreground: TerminalRGB,
		background: TerminalRGB,
		cursor: TerminalRGB? = nil,
		selection: TerminalRGB? = nil,
		ansi: [TerminalRGB]? = nil,
		font: TerminalProfileFont? = nil
	) {
		self.name = name
		self.foreground = foreground
		self.background = background
		self.cursor = cursor
		self.selection = selection
		self.font = font
		// A partial palette is worse than none: SwiftTerm ignores any array that is not
		// exactly 16 long, so a short one would silently leave the previous colors installed.
		self.ansi = ansi?.count == Self.ansiColorCount ? ansi : nil
	}

	public init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		try self.init(
			name: container.decode(String.self, forKey: .name),
			foreground: container.decode(TerminalRGB.self, forKey: .foreground),
			background: container.decode(TerminalRGB.self, forKey: .background),
			cursor: container.decodeIfPresent(TerminalRGB.self, forKey: .cursor),
			selection: container.decodeIfPresent(TerminalRGB.self, forKey: .selection),
			ansi: container.decodeIfPresent([TerminalRGB].self, forKey: .ansi),
			font: container.decodeIfPresent(TerminalProfileFont.self, forKey: .font)
		)
	}
}
