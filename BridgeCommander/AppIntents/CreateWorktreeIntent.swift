import AppIntents
import Foundation
import GitCore
import RepositoryFeature

/// Creates a worktree for a tracked repository without opening the dialog. Exposed to Siri,
/// Spotlight and Shortcuts (including Apple Intelligence actions there) via
/// `BridgeCommanderShortcuts`.
struct CreateWorktreeIntent: AppIntent {
	static let title: LocalizedStringResource = "Create Worktree"
	static let description = IntentDescription(
		"Creates a git worktree for a repository tracked in Bridge Commander. An existing branch is checked out; otherwise a new branch is created from the base branch.",
		categoryName: "Worktrees"
	)

	@Parameter(
		title: "Repository",
		requestValueDialog: "Which repository?"
	)
	var repository: RepositoryEntity

	@Parameter(
		title: "Branch Name",
		requestValueDialog: "What should the branch be called?"
	)
	var branchName: String

	@Parameter(
		title: "Base Branch",
		description: "The branch a new branch starts from. Defaults to the repository's default branch."
	)
	var baseBranch: String?

	static var parameterSummary: some ParameterSummary {
		Summary("Create worktree \(\.$branchName) in \(\.$repository)") {
			\.$baseBranch
		}
	}

	func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
		let result = try await ExternalWorktreeCreator.create(
			repositoryPath: repository.id,
			branchName: branchName,
			baseBranch: baseBranch
		)
		let plan = result.plan
		var message = plan.createNewBranch
			? "Created worktree \(plan.branchName) in \(repository.name) from \(plan.baseBranch)."
			: "Created worktree for the existing branch \(plan.branchName) in \(repository.name)."
		if let copyResult = result.copyResult, copyResult.hasWarnings {
			message += " Some files configured to be copied into it could not be copied."
		}
		return .result(value: result.worktreeURL.path, dialog: "\(message)")
	}
}
