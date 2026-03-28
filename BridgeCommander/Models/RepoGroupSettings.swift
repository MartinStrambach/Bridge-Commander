// BridgeCommander/Models/RepoGroupSettings.swift
import Foundation

nonisolated struct RepoGroupSettings: Codable, Equatable, Sendable {
    var supportsIOS: Bool = false
    var supportsAndroid: Bool = false
    /// Configurable only when both supportsIOS && supportsAndroid.
    /// Used by built-in Terminal, Claude Code, and Android Studio.
    /// When only one or neither platform is enabled this is treated as empty (repo root).
    var mobileSubfolderPath: String = ""
    /// Used by Tuist and Xcode. Shown whenever supportsIOS is true.
    var iosSubfolderPath: String = ""
    /// When false, the Tuist button is hidden even if supportsIOS is true.
    var supportsTuist: Bool = false
    /// Regex pattern to extract ticket IDs from branch names (e.g. "MOB-[0-9]+").
    /// When empty, ticket parsing is disabled — ticket button, YouTrack fetch, and branch formatting are all suppressed.
    var ticketIdRegex: String = ""

    // Memberwise initializer with default values
    init(
        supportsIOS: Bool = false,
        supportsAndroid: Bool = false,
        mobileSubfolderPath: String = "",
        iosSubfolderPath: String = "",
        supportsTuist: Bool = false,
        ticketIdRegex: String = ""
    ) {
        self.supportsIOS = supportsIOS
        self.supportsAndroid = supportsAndroid
        self.mobileSubfolderPath = mobileSubfolderPath
        self.iosSubfolderPath = iosSubfolderPath
        self.supportsTuist = supportsTuist
        self.ticketIdRegex = ticketIdRegex
    }

    // Custom decoder: uses decodeIfPresent so keys missing from older JSON
    // (saved before a property was added) fall back to defaults instead of
    // throwing. Without this, TCA's FileStorageKey resets the entire store to
    // empty on any keyNotFound error, wiping all saved presets.
    //
    // CONVENTION: when adding a new property, add:
    //   1. A parameter (with the same default) to the memberwise init above.
    //   2. A corresponding decodeIfPresent line here with the same default value.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        supportsIOS         = try c.decodeIfPresent(Bool.self,   forKey: .supportsIOS)         ?? false
        supportsAndroid     = try c.decodeIfPresent(Bool.self,   forKey: .supportsAndroid)     ?? false
        mobileSubfolderPath = try c.decodeIfPresent(String.self, forKey: .mobileSubfolderPath) ?? ""
        iosSubfolderPath    = try c.decodeIfPresent(String.self, forKey: .iosSubfolderPath)    ?? ""
        supportsTuist       = try c.decodeIfPresent(Bool.self,   forKey: .supportsTuist)       ?? false
        ticketIdRegex       = try c.decodeIfPresent(String.self, forKey: .ticketIdRegex)       ?? ""
    }
}
