import Combine
import Foundation
import SwiftUI

@MainActor
class RepositoryScanner: ObservableObject {
	@Published
	var repositories: [Repository] = []
	@Published
	var isScanning: Bool = false
	@Published
	var selectedDirectory: String?
	@Published
	var errorMessage: String?

	/// Prompts the user to select a directory and scans it
	func selectAndScanDirectory() {
		let panel = NSOpenPanel()
		panel.canChooseFiles = false
		panel.canChooseDirectories = true
		panel.allowsMultipleSelection = false
		panel.message = "Select a directory to scan for Git repositories"

		panel.begin { [weak self] response in
			guard let self else {
				return
			}

			if response == .OK, let url = panel.url {
				Task {
					await self.scanDirectory(at: url)
				}
			}
		}
	}

	/// Scans a directory for Git repositories
	/// - Parameter url: The directory URL to scan
	func scanDirectory(at url: URL) async {
		isScanning = true
		errorMessage = nil
		selectedDirectory = url.path
		repositories = []

		do {
			let foundRepositories = await GitDetector.scanForRepositories(at: url)
			repositories = foundRepositories
		}
		catch {
			errorMessage = "Error scanning directory: \(error.localizedDescription)"
		}

		isScanning = false

		// Fetch status information asynchronously in the background
		fetchStatusForRepositories()

		// Fetch PR URLs asynchronously in the background
		fetchPRUrlsForRepositories()
	}

	/// Clears the current scan results
	func clearResults() {
		repositories = []
		selectedDirectory = nil
		errorMessage = nil
	}

	/// Fetches status (changed files count) for all repositories asynchronously in the background
	private func fetchStatusForRepositories() {
		// Create a background task to fetch status for each repository
		Task {
			for (index, repository) in repositories.enumerated() {
				// Skip if already has status info
				if repository.unstagedChangesCount > 0 || repository.stagedChangesCount > 0 {
					continue
				}

				// Fetch both counts with a single git status call
				let changes = GitStatusDetector.getChangesCount(at: repository.path)

				// Update repository on main thread
				await MainActor.run {
					guard index < repositories.count else {
						return
					}

					repositories[index] = Repository(
						name: repositories[index].name,
						path: repositories[index].path,
						isWorktree: repositories[index].isWorktree,
						branchName: repositories[index].branchName,
						isMergeInProgress: repositories[index].isMergeInProgress,
						unstagedChangesCount: changes.unstagedCount,
						stagedChangesCount: changes.stagedCount
					)
				}
			}
		}
	}

	/// Fetches YouTrack issue details (PR URLs and code review fields) for all repositories
	private func fetchPRUrlsForRepositories() {
		Task {
			// Check if valid token is available
			let authToken = UserDefaults.standard.string(forKey: "youtrackAuthToken") ?? ""
			guard !authToken.isEmpty else {
				print("RepositoryScanner: Skipping YouTrack fetch (no valid auth token configured)")
				return
			}

			for (index, repository) in repositories.enumerated() {
				// Skip if no ticket ID
				guard let ticketId = repository.ticketId else {
					print("RepositoryScanner: Skipping YouTrack fetch for \(repository.name) (no ticket ID)")
					continue
				}

				// Fetch all issue details from YouTrack
				let (prUrl, androidCR, iosCR, androidReviewerName, iosReviewerName) = await YouTrackService
					.fetchIssueDetails(for: ticketId)

				await MainActor.run {
					guard index < repositories.count else {
						return
					}

					repositories[index].prUrl = prUrl
					repositories[index].androidCR = androidCR
					repositories[index].iosCR = iosCR
					repositories[index].androidReviewerName = androidReviewerName
					repositories[index].iosReviewerName = iosReviewerName
				}
			}
		}
	}
}
