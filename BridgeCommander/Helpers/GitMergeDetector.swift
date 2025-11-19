//
//  GitMergeDetector.swift
//  Bridge Commander
//
//  Helper for detecting Git merge status
//

import Foundation

struct GitMergeDetector {

    /// Checks if a repository is currently in the middle of a merge
    /// - Parameter path: The path to the Git repository
    /// - Returns: true if merge is in progress, false otherwise
    static func isMergeInProgress(at path: String) -> Bool {
        let mergeHeadPath = (path as NSString).appendingPathComponent(".git/MERGE_HEAD")

        // Check if MERGE_HEAD file exists - this indicates an ongoing merge
        return FileManager.default.fileExists(atPath: mergeHeadPath)
    }

    /// Checks if a repository is currently in the middle of a rebase
    /// - Parameter path: The path to the Git repository
    /// - Returns: true if rebase is in progress, false otherwise
    static func isRebaseInProgress(at path: String) -> Bool {
        let gitPath = (path as NSString).appendingPathComponent(".git")
        var isDirectory: ObjCBool = false
        let gitExists = FileManager.default.fileExists(atPath: gitPath, isDirectory: &isDirectory)

        guard gitExists else {
            return false
        }

        // If .git is a file (worktree), read it to find the actual git directory
        let actualGitPath: String
        if !isDirectory.boolValue {
            // It's a worktree
            guard let gitFileContent = try? String(contentsOfFile: gitPath, encoding: .utf8) else {
                return false
            }

            let trimmed = gitFileContent.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("gitdir:") {
                let gitDir = trimmed.replacingOccurrences(of: "gitdir:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                actualGitPath = gitDir
            } else {
                return false
            }
        } else {
            actualGitPath = gitPath
        }

        // Check for rebase-merge or rebase-apply directories
        let rebaseMergePath = (actualGitPath as NSString).appendingPathComponent("rebase-merge")
        let rebaseApplyPath = (actualGitPath as NSString).appendingPathComponent("rebase-apply")

        return FileManager.default.fileExists(atPath: rebaseMergePath) ||
               FileManager.default.fileExists(atPath: rebaseApplyPath)
    }

    /// Checks if a repository has any ongoing git operation (merge, rebase, etc.)
    /// - Parameter path: The path to the Git repository
    /// - Returns: true if any git operation is in progress, false otherwise
    static func isGitOperationInProgress(at path: String) -> Bool {
        return isMergeInProgress(at: path) || isRebaseInProgress(at: path)
    }
}
