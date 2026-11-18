import Foundation

/// Unified error type for all Git operations
public enum GitError: LocalizedError, Equatable {
	case pullFailed(String)
	case pushFailed(String)
	case fetchFailed(String)
	case mergeFailed(String)
	case checkoutFailed(String)
	case stashFailed(String)
	case stashApplyFailed(String)
	case stashPopFailed(String)
	case stashDropFailed(String)
	case abortMergeFailed(String)
	case discardFailed(String)
	case worktreeCreationFailed(String)
	case worktreeRemovalFailed(String)
	case branchDeletionFailed(String)
	case stagingFailed(String)
	case projectGenerationFailed(String)
	case commitFailed(String)
	case fileOperationFailed(String)
	case logFailed(String)
	case cherryPickFailed(String)
	case revertFailed(String)
	case branchCreationFailed(String)

	public var errorDescription: String? {
		switch self {
		case let .pullFailed(message):
			"Failed to pull: \(message)"
		case let .pushFailed(message):
			"Failed to push: \(message)"
		case let .fetchFailed(message):
			"Failed to fetch: \(message)"
		case let .mergeFailed(message):
			"Failed to merge: \(message)"
		case let .checkoutFailed(message):
			"Failed to checkout: \(message)"
		case let .stashFailed(message):
			"Failed to stash: \(message)"
		case let .stashApplyFailed(message):
			"Failed to apply stash: \(message)"
		case let .stashPopFailed(message):
			"Failed to pop stash: \(message)"
		case let .stashDropFailed(message):
			"Failed to clear stash: \(message)"
		case let .abortMergeFailed(message):
			"Failed to abort merge: \(message)"
		case let .discardFailed(message):
			"Failed to discard changes: \(message)"
		case let .worktreeCreationFailed(message):
			"Failed to create worktree: \(message)"
		case let .worktreeRemovalFailed(message):
			"Failed to remove worktree: \(message)"
		case let .branchDeletionFailed(message):
			"Failed to delete branch: \(message)"
		case let .stagingFailed(message):
			"Operation failed: \(message)"
		case let .projectGenerationFailed(message):
			"Failed to generate project: \(message)"
		case let .commitFailed(message):
			"Failed to commit: \(message)"
		case let .fileOperationFailed(message):
			"File operation failed: \(message)"
		case let .logFailed(message):
			"Failed to load commit history: \(message)"
		case let .cherryPickFailed(message):
			"Failed to cherry-pick: \(message)"
		case let .revertFailed(message):
			"Failed to revert: \(message)"
		case let .branchCreationFailed(message):
			"Failed to create branch: \(message)"
		}
	}

	/// The branch git refused to push because the remote branch has commits the local one
	/// doesn't — after a rebase or amend, its pre-rewrite commits. Git marks the refused ref
	/// `! [rejected]        <local> -> <remote> (non-fast-forward)`.
	///
	/// Nil unless that is the push's only refused ref: a force push is offered for exactly the
	/// branch named, and with `push.default=matching` a push can refuse several. Also nil for
	/// `(fetch first)`, where the remote has commits we have never fetched: a force push with
	/// lease would refuse those anyway.
	public var nonFastForwardRejection: GitRejectedPush? {
		guard case let .pushFailed(message) = self else {
			return nil
		}

		let rejected = message
			.split(whereSeparator: \.isNewline)
			.map { $0.trimmingCharacters(in: .whitespaces) }
			.filter { $0.hasPrefix("! [rejected]") }
		guard rejected.count == 1, let line = rejected.first, line.hasSuffix(" (non-fast-forward)") else {
			return nil
		}

		let refs = line
			.dropFirst("! [rejected]".count)
			.dropLast(" (non-fast-forward)".count)
			.trimmingCharacters(in: .whitespaces)
			.components(separatedBy: " -> ")
		guard refs.count == 2 else {
			return nil
		}

		return GitRejectedPush(localBranch: Self.shortBranchName(refs[0]), remoteBranch: Self.shortBranchName(refs[1]))
	}

	private static func shortBranchName(_ ref: String) -> String {
		ref.hasPrefix("refs/heads/") ? String(ref.dropFirst("refs/heads/".count)) : ref
	}
}

/// A local branch git refused to push onto its remote branch (`GitError.nonFastForwardRejection`).
public struct GitRejectedPush: Equatable, Sendable {
	public let localBranch: String
	public let remoteBranch: String

	public init(localBranch: String, remoteBranch: String) {
		self.localBranch = localBranch
		self.remoteBranch = remoteBranch
	}
}
