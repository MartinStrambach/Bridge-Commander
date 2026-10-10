import Foundation

/// Runs the staging panel's writes to one working tree one at a time, in the order they were
/// asked for.
///
/// Each of them takes `.git/index.lock`, and git fails a second writer outright ("index.lock: File
/// exists") rather than waiting, so two checkboxes ticked a moment apart used to end in an error
/// alert. Queueing keeps every request instead of dropping the later one.
///
/// Keyed by working tree path: each worktree has an index of its own.
actor GitIndexWriteQueue {
	static let shared = GitIndexWriteQueue()

	/// The last write queued for each path; a new one waits for it before starting.
	private var tails: [String: Task<Void, Never>] = [:]

	func run(at path: String, _ operation: @escaping @Sendable () async throws -> Void) async throws {
		let previous = tails[path]
		// Unstructured, so a caller that is cancelled while waiting does not cancel a write that
		// has already been promised to the ones queued after it.
		let write = Task {
			await previous?.value
			try await operation()
		}
		let tail = Task { _ = await write.result }
		tails[path] = tail
		defer {
			if tails[path] == tail {
				tails[path] = nil
			}
		}
		try await write.value
	}
}
