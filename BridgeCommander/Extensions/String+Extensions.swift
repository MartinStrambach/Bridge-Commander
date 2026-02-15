import Foundation

nonisolated extension String {
	/// Returns true if the string contains "Already up to date" or "Already up-to-date"
	var isAlreadyUpToDate: Bool {
		contains("Already up to date") || contains("Already up-to-date")
	}
}

nonisolated extension ProcessResult {
	/// Returns the output string trimmed of whitespace and newlines
	var trimmedOutput: String {
		outputString.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	/// Returns the error string trimmed of whitespace and newlines
	var trimmedError: String {
		errorString.trimmingCharacters(in: .whitespacesAndNewlines)
	}
}
