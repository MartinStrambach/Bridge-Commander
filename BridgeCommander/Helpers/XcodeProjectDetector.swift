//
//  XcodeProjectDetector.swift
//  Bridge Commander
//
//  Helper for detecting Xcode projects and workspaces
//

import Foundation

struct XcodeProjectDetector {

    /// Finds an Xcode workspace or project in the ios/Flashscore subfolder
    /// - Parameter repositoryPath: The repository root path
    /// - Returns: Path to .xcworkspace or .xcodeproj, or nil if not found
    /// - Note: Prioritizes .xcworkspace over .xcodeproj
    static func findXcodeProject(in repositoryPath: String) -> String? {
        let fileManager = FileManager.default

        // Build path to ios/Flashscore subfolder
        let iosFlashscorePath = (repositoryPath as NSString).appendingPathComponent("ios/Flashscore")

        // Check if ios/Flashscore directory exists
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: iosFlashscorePath, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }

        // Get directory contents
        guard let contents = try? fileManager.contentsOfDirectory(atPath: iosFlashscorePath) else {
            return nil
        }

        // Priority 1: Look for .xcworkspace
        if let workspace = contents.first(where: { $0.hasSuffix(".xcworkspace") }) {
            return (iosFlashscorePath as NSString).appendingPathComponent(workspace)
        }

        // Priority 2: Look for .xcodeproj
        if let project = contents.first(where: { $0.hasSuffix(".xcodeproj") }) {
            return (iosFlashscorePath as NSString).appendingPathComponent(project)
        }

        return nil
    }

    /// Checks if an Xcode project or workspace exists in the ios/Flashscore subfolder
    /// - Parameter repositoryPath: The repository root path
    /// - Returns: True if a project or workspace exists
    static func hasXcodeProject(in repositoryPath: String) -> Bool {
        return findXcodeProject(in: repositoryPath) != nil
    }

    /// Returns the ios/Flashscore subfolder path for a repository
    /// - Parameter repositoryPath: The repository root path
    /// - Returns: Path to ios/Flashscore subfolder
    static func getIosFlashscorePath(in repositoryPath: String) -> String {
        return (repositoryPath as NSString).appendingPathComponent("ios/Flashscore")
    }
}
