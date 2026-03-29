import Foundation

public nonisolated extension String {
	/// Returns true if the string contains "Already up to date" or "Already up-to-date"
	var isAlreadyUpToDate: Bool {
		contains("Already up to date") || contains("Already up-to-date")
	}
}
