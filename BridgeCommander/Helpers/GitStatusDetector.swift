//
//  GitStatusDetector.swift
//  Bridge Commander
//
//  Helper for detecting Git status information (changed files)
//

import Foundation

struct GitChanges {
    let unstagedCount: Int
    let stagedCount: Int
}

struct GitStatusDetector {

    /// Detects both staged and unstaged changes in a repository
    /// Uses `git ls-files -m` for unstaged changes and `git diff --name-only --cached` for staged changes
    /// - Parameter path: The path to the Git repository
    /// - Returns: A GitChanges struct with both counts
    static func getChangesCount(at path: String) -> GitChanges {
        let unstagedCount = getUnstagedCount(at: path)
        let stagedCount = getStagedCount(at: path)
        return GitChanges(unstagedCount: unstagedCount, stagedCount: stagedCount)
    }

    /// Counts unstaged changes using git ls-files -m
    private static func getUnstagedCount(at path: String) -> Int {
        let process = Process()
        process.currentDirectoryPath = path
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["ls-files", "-m"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                return 0
            }

            // Count non-empty lines
            let count = output.split(separator: "\n").count
            return output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : count
        } catch {
            return 0
        }
    }

    /// Counts staged changes using git diff --name-only --cached
    private static func getStagedCount(at path: String) -> Int {
        let process = Process()
        process.currentDirectoryPath = path
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["diff", "--name-only", "--cached"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                return 0
            }

            // Count non-empty lines
            let count = output.split(separator: "\n").count
            return output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : count
        } catch {
            return 0
        }
    }
}
