import ComposableArchitecture
import Foundation
import GitCore

// The graph's write actions, offered from the commit menu: check out, branch, worktree,
// cherry-pick, revert. Everything else in the graph only reads, so these are the one place it
// can change the repository, and each of them reloads the graph and tells the presenter after.

/// The name prompt behind "New Branch…" and "New Worktree…".
public struct BranchForm: Equatable, Identifiable, Sendable {
	public enum Kind: Equatable, Sendable {
		case branch
		case worktree
	}

	let kind: Kind
	let commit: GitLogCommit

	/// As typed, with whitespace already turned into underscores (git rejects it in a ref name).
	var name = ""

	/// Whether a new branch is also checked out. A worktree always gets its branch checked out.
	var checksOut = true

	public var id: String { "\(kind)-\(commit.hash)" }

	var canSubmit: Bool {
		!branchName.isEmpty
	}

	/// The name the branch is created with.
	var branchName: String {
		GitBranchNameSanitizer.sanitize(name.trimmingCharacters(in: .whitespacesAndNewlines))
	}
}

@CasePathable
public enum CommitAction: Equatable, Sendable {
	case checkoutBranchTapped(String)
	case checkoutRemoteBranchTapped(String)
	case checkoutCommitTapped(GitLogCommit)
	case cherryPickTapped(GitLogCommit)
	case revertTapped(GitLogCommit)
	case newBranchTapped(GitLogCommit)
	case newWorktreeTapped(GitLogCommit)

	case branchFormNameChanged(String)
	case branchFormChecksOutChanged(Bool)
	case branchFormSubmitted
	case branchFormCancelled

	case finished(Result)

	/// The confirmations asked before an action that changes the current branch, and the
	/// choice offered when one stops on conflicts.
	public enum Alert: Equatable, Sendable {
		case checkoutCommit(GitLogCommit)
		case cherryPick(GitLogCommit)
		case revert(GitLogCommit)
		case abort(GitSequencerOperation)
	}

	public enum Result: Equatable, Sendable {
		case succeeded
		case stoppedOnConflicts(GitSequencerOperation, files: [String])
		case worktreeCreated(GitWorktreeFromCommit)
		case failed(title: String, message: String)
	}
}

extension GitGraphReducer.State {
	/// The current branch as a confirmation names it.
	var headDescription: String {
		guard let head = rows.first(where: \.commit.isHead)?.commit else {
			// Not loaded, e.g. under a search that HEAD does not match.
			return "the current branch"
		}

		if let branch = head.refs.first(where: { $0.isHead && $0.kind == .localBranch }) {
			return "“\(branch.name)”"
		}
		return "the detached HEAD"
	}
}

extension GitGraphReducer {
	func reduce(commitAction action: CommitAction, state: inout State) -> Effect<Action> {
		switch action {
		case let .checkoutBranchTapped(branch):
			return run("Checking out \(branch)…", failureTitle: "Checkout Failed", state: &state) { [gitCommitActions, path = state.repositoryPath] in
				try await gitCommitActions.checkoutBranch(branch, path)
				return .succeeded
			}

		case let .checkoutRemoteBranchTapped(remoteBranch):
			return run("Checking out \(remoteBranch)…", failureTitle: "Checkout Failed", state: &state) { [gitCommitActions, path = state.repositoryPath] in
				try await gitCommitActions.checkoutRemoteBranch(remoteBranch, path)
				return .succeeded
			}

		case let .checkoutCommitTapped(commit):
			state.alert = AlertState {
				TextState("Check out \(commit.shortHash)?")
			} actions: {
				ButtonState(action: .checkoutCommit(commit)) {
					TextState("Check Out")
				}
				ButtonState(role: .cancel) {
					TextState("Cancel")
				}
			} message: {
				TextState(
					"HEAD will be detached at “\(commit.subject)”. Commits made there belong to no branch "
						+ "until you create one for them."
				)
			}
			return .none

		case let .cherryPickTapped(commit):
			state.alert = AlertState {
				TextState("Cherry-pick \(commit.shortHash) onto \(state.headDescription)?")
			} actions: {
				ButtonState(action: .cherryPick(commit)) {
					TextState("Cherry-Pick")
				}
				ButtonState(role: .cancel) {
					TextState("Cancel")
				}
			} message: {
				TextState(Self.confirmationMessage(for: commit, adds: "a copy of"))
			}
			return .none

		case let .revertTapped(commit):
			state.alert = AlertState {
				TextState("Revert \(commit.shortHash) on \(state.headDescription)?")
			} actions: {
				ButtonState(action: .revert(commit)) {
					TextState("Revert")
				}
				ButtonState(role: .cancel) {
					TextState("Cancel")
				}
			} message: {
				TextState(Self.confirmationMessage(for: commit, adds: "a commit undoing"))
			}
			return .none

		case let .newBranchTapped(commit):
			state.branchForm = BranchForm(kind: .branch, commit: commit)
			return .none

		case let .newWorktreeTapped(commit):
			state.branchForm = BranchForm(kind: .worktree, commit: commit)
			return .none

		case let .branchFormNameChanged(name):
			state.branchForm?.name = GitBranchNameSanitizer.sanitize(name)
			return .none

		case let .branchFormChecksOutChanged(checksOut):
			state.branchForm?.checksOut = checksOut
			return .none

		case .branchFormCancelled:
			state.branchForm = nil
			return .none

		case .branchFormSubmitted:
			guard let form = state.branchForm, form.canSubmit else {
				return .none
			}

			state.branchForm = nil
			let name = form.branchName
			let hash = form.commit.hash
			switch form.kind {
			case .branch:
				return run("Creating \(name)…", failureTitle: "Branch Not Created", state: &state) { [gitCommitActions, path = state.repositoryPath, checksOut = form.checksOut] in
					try await gitCommitActions.createBranch(name, hash, checksOut, path)
					return .succeeded
				}

			case .worktree:
				return run("Creating worktree \(name)…", failureTitle: "Worktree Not Created", state: &state) { [
					gitCommitActions,
					path = state.repositoryPath,
					basePath = state.worktreeBasePath,
					copyPaths = state.worktreeCopyPaths
				] in
					try await .worktreeCreated(gitCommitActions.createWorktree(name, hash, path, basePath, copyPaths))
				}
			}

		case let .finished(result):
			state.runningCommitAction = nil
			switch result {
			case .succeeded:
				return .merge(loadCommits(state: &state), .send(.delegate(.repositoryChanged)))

			case let .stoppedOnConflicts(operation, files):
				state.alert = Self.conflictAlert(for: operation, files: files, head: state.headDescription)
				return .merge(loadCommits(state: &state), .send(.delegate(.repositoryChanged)))

			case let .worktreeCreated(worktree):
				state.alert = Self.worktreeCreatedAlert(for: worktree)
				return .merge(loadCommits(state: &state), .send(.delegate(.worktreeCreated(path: worktree.folder.path))))

			case let .failed(title, message):
				state.alert = AlertState {
					TextState(title)
				} actions: {
					ButtonState(role: .cancel) {
						TextState("OK")
					}
				} message: {
					TextState(message)
				}
				return .none
			}
		}
	}

	func reduce(alertAction action: CommitAction.Alert, state: inout State) -> Effect<Action> {
		let path = state.repositoryPath
		switch action {
		case let .checkoutCommit(commit):
			return run("Checking out \(commit.shortHash)…", failureTitle: "Checkout Failed", state: &state) { [gitCommitActions] in
				try await gitCommitActions.checkoutDetached(commit.hash, path)
				return .succeeded
			}

		case let .cherryPick(commit):
			return run("Cherry-picking \(commit.shortHash)…", failureTitle: "Cherry-Pick Failed", state: &state) { [gitCommitActions] in
				try await Self.result(of: gitCommitActions.apply(.cherryPick, commit, path), operation: .cherryPick)
			}

		case let .revert(commit):
			return run("Reverting \(commit.shortHash)…", failureTitle: "Revert Failed", state: &state) { [gitCommitActions] in
				try await Self.result(of: gitCommitActions.apply(.revert, commit, path), operation: .revert)
			}

		case let .abort(operation):
			return run("Aborting the \(operation.noun)…", failureTitle: "Abort Failed", state: &state) { [gitCommitActions] in
				try await gitCommitActions.abort(operation, path)
				return .succeeded
			}
		}
	}

	/// Runs `work` as the one write action in flight, reporting a thrown error as `failureTitle`.
	private func run(
		_ description: String,
		failureTitle: String,
		state: inout State,
		_ work: @escaping @Sendable () async throws -> CommitAction.Result
	) -> Effect<Action> {
		guard state.runningCommitAction == nil else {
			return .none
		}

		state.runningCommitAction = description
		return .run { send in
			do {
				try await send(.commitAction(.finished(work())))
			}
			catch {
				await send(.commitAction(.finished(.failed(title: failureTitle, message: error.localizedDescription))))
			}
		}
	}

	private static func result(of outcome: GitSequencerOutcome, operation: GitSequencerOperation) -> CommitAction.Result {
		switch outcome {
		case .committed:
			.succeeded
		case let .conflicts(files):
			.stoppedOnConflicts(operation, files: files)
		}
	}

	private static func confirmationMessage(for commit: GitLogCommit, adds what: String) -> String {
		var message = "Adds \(what) “\(commit.subject)”."
		if commit.isMerge {
			// The same side the graph's diff shows for a merge.
			message += " It is a merge, so its changes are taken against its first parent."
		}
		return message
	}

	private static func conflictAlert(
		for operation: GitSequencerOperation,
		files: [String],
		head: String
	) -> AlertState<CommitAction.Alert> {
		let listed = files.prefix(10).map { "• \($0)" }
		let more = files.count > listed.count ? ["…and \(files.count - listed.count) more"] : []
		return AlertState {
			TextState("The \(operation.noun) stopped on conflicts")
		} actions: {
			ButtonState(role: .destructive, action: .abort(operation)) {
				TextState("Abort \(operation.title)")
			}
			ButtonState(role: .cancel) {
				TextState("Resolve Later")
			}
		} message: {
			TextState(
				(["Conflicted files:"] + listed + more).joined(separator: "\n")
					+ "\n\nResolve them and commit from the staging panel, or abort to put \(head) back as it was."
			)
		}
	}

	private static func worktreeCreatedAlert(for worktree: GitWorktreeFromCommit) -> AlertState<CommitAction.Alert> {
		var lines = [worktree.folder.path]
		if let copy = worktree.copyResult, copy.hasWarnings {
			if !copy.missing.isEmpty {
				lines += ["", "Missing in the main repository, not copied:"] + copy.missing.map { "• \($0)" }
			}
			if !copy.failed.isEmpty {
				lines += ["", "Failed to copy:"] + copy.failed.map { "• \($0.path) — \($0.reason)" }
			}
		}

		return AlertState {
			TextState("Worktree created")
		} actions: {
			ButtonState(role: .cancel) {
				TextState("OK")
			}
		} message: {
			TextState(lines.joined(separator: "\n"))
		}
	}
}

extension GitSequencerOperation {
	var noun: String {
		switch self {
		case .cherryPick:
			"cherry-pick"
		case .revert:
			"revert"
		}
	}

	var title: String {
		switch self {
		case .cherryPick:
			"Cherry-Pick"
		case .revert:
			"Revert"
		}
	}
}
