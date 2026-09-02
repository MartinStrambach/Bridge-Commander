import Foundation

/// Unified error type for all Git operations
public enum GitError: LocalizedError, Equatable {
	case pullFailed(String)
	case pushFailed(String)
	case fetchFailed(String)
	case mergeFailed(String)
	case checkoutFailed(String)
	case stashFailed(String)
	case stashPopFailed(String)
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
		case let .stashPopFailed(message):
			"Failed to pop stash: \(message)"
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
		}
	}
}
