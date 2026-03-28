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
}
