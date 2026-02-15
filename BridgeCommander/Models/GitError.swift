import Foundation

/// Unified error type for all Git operations
enum GitError: LocalizedError, Equatable, Sendable {
	case pullFailed(String)
	case pushFailed(String)
	case fetchFailed(String)
	case mergeFailed(String)
	case stashFailed(String)
	case stashPopFailed(String)
	case abortMergeFailed(String)
	case worktreeCreationFailed(String)
	case worktreeRemovalFailed(String)
	case stagingFailed(String)
	case projectGenerationFailed(String)
	case fileOperationFailed(String)

	var errorDescription: String? {
		switch self {
		case let .pullFailed(message):
			"Failed to pull: \(message)"
		case let .pushFailed(message):
			"Failed to push: \(message)"
		case let .fetchFailed(message):
			"Failed to fetch: \(message)"
		case let .mergeFailed(message):
			"Failed to merge: \(message)"
		case let .stashFailed(message):
			"Failed to stash: \(message)"
		case let .stashPopFailed(message):
			"Failed to pop stash: \(message)"
		case let .abortMergeFailed(message):
			"Failed to abort merge: \(message)"
		case let .worktreeCreationFailed(message):
			"Failed to create worktree: \(message)"
		case let .worktreeRemovalFailed(message):
			"Failed to remove worktree: \(message)"
		case let .stagingFailed(message):
			"Operation failed: \(message)"
		case let .projectGenerationFailed(message):
			"Failed to generate project: \(message)"
		case let .fileOperationFailed(message):
			"File operation failed: \(message)"
		}
	}
}
