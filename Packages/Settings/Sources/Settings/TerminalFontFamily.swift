import AppKit

/// The typeface the built-in terminal renders with.
///
/// Stored as the bare font name `NSFont(name:size:)` takes, with the empty string standing for
/// "whatever the system calls monospaced" — the face SwiftTerm picked before this setting existed,
/// so an untouched install is unchanged. A sentinel rather than a hard-coded family name because
/// `NSFont.monospacedSystemFont` follows the system (SF Mono today, not necessarily tomorrow) and
/// has no public name to write down.
public enum TerminalFontFamily {

	/// The empty string: render with `NSFont.monospacedSystemFont`.
	public static let systemDefault = ""

	/// What the system default is called in the picker.
	public static let systemDefaultDisplayName = "System Monospaced"

	/// The font for a stored name and point size, falling back to the system monospaced face.
	///
	/// The fallback is not just for the sentinel: the name comes from user defaults and names a
	/// font that may since have been uninstalled, and SwiftTerm has no way to render with nothing.
	public static func resolve(name: String, size: Double) -> NSFont {
		let size = TerminalFontSize.clamped(size)
		guard !name.isEmpty, let font = NSFont(name: name, size: size) else {
			return .monospacedSystemFont(ofSize: size, weight: .regular)
		}
		return font
	}

	/// Whether a font name still resolves to an installed font.
	public static func isAvailable(name: String) -> Bool {
		name.isEmpty || NSFont(name: name, size: TerminalFontSize.default) != nil
	}

	/// The installed font families that have at least one fixed-pitch face, sorted by name.
	///
	/// Filtered rather than listing every family: a terminal draws on a character grid, so a
	/// proportional face turns every column into a ragged edge. A family qualifies on any member
	/// being fixed pitch — several monospaced families mark only their regular face.
	public static func availableMonospacedFamilies() -> [String] {
		let manager = NSFontManager.shared
		return manager.availableFontFamilies
			.filter { family in
				guard let members = manager.availableMembers(ofFontFamily: family) else {
					return false
				}
				// Each member is [postscriptName, styleName, weight, traits]; traits is an
				// NSFontTraitMask bitfield boxed as an NSNumber.
				return members.contains { member in
					guard
						member.count >= 4,
						let traits = member[3] as? UInt
					else { return false }
					return NSFontTraitMask(rawValue: traits).contains(.fixedPitchFontMask)
				}
			}
			.sorted()
	}

	/// The label for a stored name, which is the name itself except for the sentinel.
	public static func displayName(for name: String) -> String {
		name.isEmpty ? systemDefaultDisplayName : name
	}
}
