//
//  Repository.swift
//  Bridge Commander
//
//  Model representing a Git repository
//

import Foundation

struct Repository: Identifiable, Hashable {
    let id: UUID
    let name: String
    let path: String
    let isWorktree: Bool
    let branchName: String?
    let isMergeInProgress: Bool

    init(name: String, path: String, isWorktree: Bool = false, branchName: String? = nil, isMergeInProgress: Bool = false) {
        self.id = UUID()
        self.name = name
        self.path = path
        self.isWorktree = isWorktree
        self.branchName = branchName
        self.isMergeInProgress = isMergeInProgress
    }

    /// Returns the URL representation of the repository path
    var url: URL {
        URL(fileURLWithPath: path)
    }

    /// Returns a display-friendly description of the repository type
    var typeDescription: String {
        isWorktree ? "Worktree" : "Repository"
    }

    /// Extracts and returns the YouTrack ticket ID from the branch name
    var ticketId: String? {
        guard let branchName = branchName else { return nil }
        return GitBranchDetector.extractTicketId(from: branchName)
    }

    /// Returns a formatted, human-readable version of the branch name
    /// Removes prefixes (feature/fix/etc), project types, ticket numbers, and replaces underscores with spaces
    var formattedBranchName: String? {
        guard let branchName = branchName else { return nil }

        var formatted = branchName

        // 1. Remove part before first slash (feature, fix, bugfix, etc.)
        if let firstSlashIndex = formatted.firstIndex(of: "/") {
            formatted = String(formatted[formatted.index(after: firstSlashIndex)...])
        }

        // 2. Remove project type patterns like "tech-60", "mob-45" (case insensitive)
        // Pattern: word-digits followed by underscore or slash
        let projectTypePattern = "[a-zA-Z]+-\\d+[_/]"
        if let regex = try? NSRegularExpression(pattern: projectTypePattern, options: .caseInsensitive) {
            let range = NSRange(formatted.startIndex..., in: formatted)
            formatted = regex.stringByReplacingMatches(
                in: formatted,
                range: range,
                withTemplate: ""
            )
        }

        // 3. Remove ticket number (MOB-1456)
        if let ticketId = self.ticketId {
            formatted = formatted.replacingOccurrences(of: ticketId, with: "")
        }

        // 4. Replace underscores with spaces
        formatted = formatted.replacingOccurrences(of: "_", with: " ")

        // 5. Clean up: trim whitespace, remove multiple consecutive spaces, remove leading/trailing slashes
        formatted = formatted
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/ "))

        // Return nil if the result is empty
        return formatted.isEmpty ? nil : formatted
    }
}
