import Foundation
import ToolsIntegration

public nonisolated struct RepoGroupSettings: Codable, Equatable, Sendable {
	public var supportsIOS: Bool = false
	public var supportsAndroid: Bool = false
	/// Configurable only when both supportsIOS && supportsAndroid.
	/// Used by built-in Terminal, Claude Code, and Android Studio.
	/// When only one or neither platform is enabled this is treated as empty (repo root).
	public var mobileSubfolderPath: String = ""
	/// Used by Tuist and Xcode. Shown whenever supportsIOS is true.
	public var iosSubfolderPath: String = ""
	/// When false, the Tuist button is hidden even if supportsIOS is true.
	public var supportsTuist: Bool = false
	/// Regex pattern to extract ticket IDs from branch names (e.g. "MOB-[0-9]+").
	/// When empty, ticket parsing is disabled — ticket button, YouTrack fetch, and branch formatting are all
	/// suppressed.
	public var ticketIdRegex: String = ""
	/// Controls whether the Xcode button prefers .xcworkspace, .xcodeproj, or auto-detects.
	public var xcodeFilePreference: XcodeFilePreference = .auto

	/// Memberwise initializer with default values
	public init(
		supportsIOS: Bool = false,
		supportsAndroid: Bool = false,
		mobileSubfolderPath: String = "",
		iosSubfolderPath: String = "",
		supportsTuist: Bool = false,
		ticketIdRegex: String = "",
		xcodeFilePreference: XcodeFilePreference = .auto
	) {
		self.supportsIOS = supportsIOS
		self.supportsAndroid = supportsAndroid
		self.mobileSubfolderPath = mobileSubfolderPath
		self.iosSubfolderPath = iosSubfolderPath
		self.supportsTuist = supportsTuist
		self.ticketIdRegex = ticketIdRegex
		self.xcodeFilePreference = xcodeFilePreference
	}

	// Custom decoder: uses decodeIfPresent so keys missing from older JSON
	// (saved before a property was added) fall back to defaults instead of
	// throwing. Without this, TCA's FileStorageKey resets the entire store to
	// empty on any keyNotFound error, wiping all saved presets.
	//
	// CONVENTION: when adding a new property, add:
	//   1. A parameter (with the same default) to the memberwise init above.
	//   2. A corresponding decodeIfPresent line here with the same default value.
	public init(from decoder: any Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		self.supportsIOS = try c.decodeIfPresent(Bool.self, forKey: .supportsIOS) ?? false
		self.supportsAndroid = try c.decodeIfPresent(Bool.self, forKey: .supportsAndroid) ?? false
		self.mobileSubfolderPath = try c.decodeIfPresent(String.self, forKey: .mobileSubfolderPath) ?? ""
		self.iosSubfolderPath = try c.decodeIfPresent(String.self, forKey: .iosSubfolderPath) ?? ""
		self.supportsTuist = try c.decodeIfPresent(Bool.self, forKey: .supportsTuist) ?? false
		self.ticketIdRegex = try c.decodeIfPresent(String.self, forKey: .ticketIdRegex) ?? ""
		self.xcodeFilePreference = try c.decodeIfPresent(XcodeFilePreference.self, forKey: .xcodeFilePreference) ?? .auto
	}
}
