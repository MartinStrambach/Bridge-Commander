import AppKit
import Foundation

public enum TerminalProfileImportError: Error, Equatable, LocalizedError {
	case unreadableFile(name: String)
	case notAPropertyList(name: String)
	case noProfilesFound(name: String)
	case terminalPreferencesUnavailable

	public var errorDescription: String? {
		switch self {
		case let .unreadableFile(name):
			"“\(name)” could not be read."

		case let .notAPropertyList(name):
			"“\(name)” is not a property list. Terminal profiles are exported from Terminal → Settings → Profiles → Export."

		case let .noProfilesFound(name):
			"“\(name)” contains no terminal profile."

		case .terminalPreferencesUnavailable:
			"Terminal.app's settings could not be read. Open Terminal at least once so it writes its preferences."
		}
	}
}

/// Reads Terminal.app color profiles, either from an exported `.terminal` file or straight
/// out of Terminal's own preferences.
///
/// Both sources are property lists holding the same profile dictionaries, and in both the
/// colors are `NSKeyedArchiver`-encoded `NSColor` objects rather than strings — SwiftTerm has
/// no support for any of this, so the decoding lives here.
public nonisolated enum TerminalProfileImporter {
	static let terminalBundleIdentifier = "com.apple.Terminal"

	/// Terminal's per-profile plist key, in SwiftTerm's palette order: the eight normal
	/// colors followed by the eight bright ones.
	static let ansiColorKeys = [
		"ANSIBlackColor",
		"ANSIRedColor",
		"ANSIGreenColor",
		"ANSIYellowColor",
		"ANSIBlueColor",
		"ANSIMagentaColor",
		"ANSICyanColor",
		"ANSIWhiteColor",
		"ANSIBrightBlackColor",
		"ANSIBrightRedColor",
		"ANSIBrightGreenColor",
		"ANSIBrightYellowColor",
		"ANSIBrightBlueColor",
		"ANSIBrightMagentaColor",
		"ANSIBrightCyanColor",
		"ANSIBrightWhiteColor",
	]

	/// The key Terminal nests all of its profiles under in its preferences domain, and the
	/// value it writes into each profile's `type`.
	static let windowSettingsKey = "Window Settings"

	// MARK: - Sources

	/// Reads every profile Terminal.app currently has configured.
	///
	/// This goes through `cfprefsd` rather than reading the plist file directly, so it sees
	/// values Terminal has not flushed to disk yet. It requires the app to run unsandboxed —
	/// a sandboxed process gets `nil` back for another app's domain.
	public static func profilesFromTerminalApp(
		defaults: UserDefaults = .standard
	) throws -> [TerminalProfile] {
		guard let domain = defaults.persistentDomain(forName: terminalBundleIdentifier) else {
			throw TerminalProfileImportError.terminalPreferencesUnavailable
		}
		let profiles = self.profiles(fromPropertyList: domain)
		guard !profiles.isEmpty else {
			throw TerminalProfileImportError.terminalPreferencesUnavailable
		}
		return profiles
	}

	/// Reads the profile(s) in an exported `.terminal` file.
	public static func profiles(fromFileAt url: URL) throws -> [TerminalProfile] {
		let displayName = url.lastPathComponent
		// A no-op while the app is unsandboxed, and the correct thing to do if it ever is not.
		let accessed = url.startAccessingSecurityScopedResource()
		defer {
			if accessed { url.stopAccessingSecurityScopedResource() }
		}

		guard let data = try? Data(contentsOf: url) else {
			throw TerminalProfileImportError.unreadableFile(name: displayName)
		}
		guard let object = try? PropertyListSerialization.propertyList(
			from: data,
			options: [],
			format: nil
		) else {
			throw TerminalProfileImportError.notAPropertyList(name: displayName)
		}

		let fallbackName = url.deletingPathExtension().lastPathComponent
		let profiles = self.profiles(fromPropertyList: object, fallbackName: fallbackName)
		guard !profiles.isEmpty else {
			throw TerminalProfileImportError.noProfilesFound(name: displayName)
		}
		return profiles
	}

	// MARK: - Parsing

	/// Extracts every profile in a decoded property list.
	///
	/// Handles both shapes this format comes in: Terminal's preferences domain, which nests a
	/// dictionary of profiles under `Window Settings`, and an exported `.terminal` file, which
	/// *is* a single profile dictionary.
	public static func profiles(
		fromPropertyList object: Any,
		fallbackName: String = "Imported"
	) -> [TerminalProfile] {
		guard let root = object as? [String: Any] else { return [] }

		if let settings = root[windowSettingsKey] as? [String: Any] {
			return settings
				.compactMap { name, raw in profile(from: raw, fallbackName: name) }
				.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
		}

		return [profile(from: root, fallbackName: fallbackName)].compactMap(\.self)
	}

	/// Converts one profile dictionary, or returns `nil` when it does not look like a profile.
	static func profile(from raw: Any, fallbackName: String) -> TerminalProfile? {
		guard let dict = raw as? [String: Any] else { return nil }

		// Only accept a dictionary that actually is a profile, so pointing the file picker at
		// an unrelated plist reports "no profile" instead of importing a black-on-black theme
		// built entirely out of defaults.
		let isWindowSettings = dict["type"] as? String == windowSettingsKey
		let definesAnyColor = (["BackgroundColor", "TextColor"] + ansiColorKeys)
			.contains { dict[$0] != nil }
		guard isWindowSettings || definesAnyColor else { return nil }

		let name = (dict["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
		let ansi = ansiColorKeys.compactMap { color(from: dict[$0]) }

		return TerminalProfile(
			name: name.map { $0.isEmpty ? fallbackName : $0 } ?? fallbackName,
			// Terminal's own defaults for a profile that sets neither, which is what "Basic"
			// looks like on screen: black text on white.
			foreground: color(from: dict["TextColor"]) ?? TerminalRGB(red: 0, green: 0, blue: 0),
			background: color(from: dict["BackgroundColor"]) ?? TerminalRGB(red: 1, green: 1, blue: 1),
			cursor: color(from: dict["CursorColor"]),
			selection: color(from: dict["SelectionColor"]),
			// All sixteen or none: a half-decoded palette would leave the remaining slots on
			// the previous theme's colors, which reads as a rendering bug rather than a
			// half-imported profile.
			ansi: ansi.count == TerminalProfile.ansiColorCount ? ansi : nil
		)
	}

	/// Decodes one `NSKeyedArchiver`-encoded `NSColor` value.
	static func color(from value: Any?) -> TerminalRGB? {
		guard let data = value as? Data,
		      let unarchived = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)
		else {
			return nil
		}
		return TerminalRGB(unarchived)
	}
}
