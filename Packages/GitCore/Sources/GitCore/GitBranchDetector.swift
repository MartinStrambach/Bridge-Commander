import Foundation

public nonisolated enum GitBranchDetector {

	/// Extracts a ticket ID from a branch name using a regex pattern
	/// - Parameters:
	///   - branchName: The Git branch name
	///   - pattern: The regex pattern to use for extraction (e.g., "MOB-[0-9]+")
	/// - Returns: The ticket ID (e.g., "MOB-1963"), or nil if not found
	public static func extractTicketId(from branchName: String, pattern: String) -> String? {
		guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
			print("Failed to create regex for ticket extraction with pattern: \(pattern)")
			return nil
		}

		let range = NSRange(branchName.startIndex..., in: branchName)
		guard let match = regex.firstMatch(in: branchName, options: [], range: range) else {
			print("No ticket ID found in branch '\(branchName)' using pattern '\(pattern)'")
			return nil
		}
		guard let matchRange = Range(match.range, in: branchName) else {
			return nil
		}

		let ticketId = String(branchName[matchRange])
		print("Extracted ticket ID '\(ticketId)' from branch '\(branchName)' using pattern '\(pattern)'")
		return ticketId
	}

}
