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
}
