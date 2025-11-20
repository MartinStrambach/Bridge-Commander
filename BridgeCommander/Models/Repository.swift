import Foundation

struct Repository: Identifiable, Hashable {
	let id: UUID
	let name: String
	let path: String
	let isWorktree: Bool
	let branchName: String?
	let isMergeInProgress: Bool
	let unstagedChangesCount: Int
	let stagedChangesCount: Int
	let ticketId: String?
	var prUrl: String?
	var androidCR: String?
	var iosCR: String?
	var androidReviewerName: String?
	var iosReviewerName: String?

	/// Returns the URL representation of the repository path
	var url: URL {
		URL(fileURLWithPath: path)
	}

	/// Returns a display-friendly description of the repository type
	var typeDescription: String {
		isWorktree ? "Worktree" : "Repository"
	}

	/// Returns a formatted, human-readable version of the branch name
	/// Removes prefixes (feature/fix/etc), project types, ticket numbers, and replaces underscores with spaces
	var formattedBranchName: String? {
		guard let branchName else {
			return nil
		}

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
		if let ticketId {
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

	/// Returns the sort key by ticket number (or name if no ticket)
	var sortKeyByTicket: String {
		if let ticketId {
			return ticketId
		}
		return name
	}

	/// Returns the sort key by branch name
	var sortKeyByBranch: String {
		if let branchName {
			return branchName
		}
		return name
	}

	init(
		name: String,
		path: String,
		isWorktree: Bool = false,
		branchName: String? = nil,
		isMergeInProgress: Bool = false,
		unstagedChangesCount: Int = 0,
		stagedChangesCount: Int = 0
	) {
		self.id = UUID()
		self.name = name
		self.path = path
		self.isWorktree = isWorktree
		self.branchName = branchName
		self.isMergeInProgress = isMergeInProgress
		self.unstagedChangesCount = unstagedChangesCount
		self.stagedChangesCount = stagedChangesCount
		self.prUrl = nil
		self.androidCR = nil
		self.iosCR = nil
		self.androidReviewerName = nil
		self.iosReviewerName = nil
		self.ticketId = GitBranchDetector.extractTicketId(from: branchName ?? "")
	}

}
