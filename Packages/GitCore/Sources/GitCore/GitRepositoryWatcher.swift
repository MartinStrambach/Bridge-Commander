import Dependencies
import DependenciesMacros
import Foundation
import ProcessExecution

// MARK: - Client

/// Reports changes on disk to repositories, so their rows can update without waiting for the
/// periodic refresh — a checkout in the built-in terminal, an edit in an editor, a fetch.
@DependencyClient
public struct GitRepositoryWatcherClient: Sendable {
	/// Batches of changes to `repositoryPaths` until the stream is dropped. Each repository
	/// appears at most once per batch, under the path it was passed in as.
	public var changes: @Sendable (_ repositoryPaths: [String]) -> AsyncStream<[GitRepositoryChange]> = { _ in
		.finished
	}
}

extension GitRepositoryWatcherClient: DependencyKey {
	public static var liveValue: GitRepositoryWatcherClient {
		GitRepositoryWatcherClient(
			changes: { repositoryPaths in
				GitRepositoryWatcher.changes(repositoryPaths: repositoryPaths)
			}
		)
	}
}

extension GitRepositoryWatcherClient: TestDependencyKey {
	/// Nothing ever changes on disk in a test unless the test says so. Not left unimplemented:
	/// every scan starts a watch, and most tests that scan are about something else.
	public static var testValue: GitRepositoryWatcherClient {
		GitRepositoryWatcherClient(changes: { _ in .finished })
	}
}

// MARK: - Live Implementation

nonisolated enum GitRepositoryWatcher {
	/// How long FSEvents gathers events into one batch. Short enough that a checkout shows up
	/// as it finishes, long enough that a build's output arrives as a few batches, not thousands.
	static let latency: TimeInterval = 0.3

	/// Paths per `git check-ignore` call, keeping a large batch well under `ARG_MAX`.
	static let checkIgnoreChunkSize = 200

	static func changes(repositoryPaths: [String]) -> AsyncStream<[GitRepositoryChange]> {
		AsyncStream { continuation in
			let targets = repositoryPaths.compactMap(GitWatchTarget.init(repositoryPath:))
			let roots = GitChangeClassifier.watchRoots(for: targets)
			let (batches, batchContinuation) = AsyncStream<[FileSystemEvent]>.makeStream()
			guard
				!roots.isEmpty,
				let stream = FileSystemEventStream(
					paths: roots,
					latency: latency,
					deliver: { batchContinuation.yield($0) }
				)
			else {
				continuation.finish()
				return
			}

			// One batch at a time, in arrival order: handling one may wait on `git check-ignore`.
			let task = Task {
				for await batch in batches {
					let changes = await changes(in: batch, targets: targets)
					if !changes.isEmpty {
						continuation.yield(changes)
					}
				}
				continuation.finish()
			}
			stream.start()

			continuation.onTermination = { _ in
				stream.stop()
				batchContinuation.finish()
				task.cancel()
			}
		}
	}

	static func changes(in batch: [FileSystemEvent], targets: [GitWatchTarget]) async -> [GitRepositoryChange] {
		var classification = GitChangeClassifier.classify(batch, targets: targets)
		for (repositoryPath, paths) in classification.workingTreePaths {
			guard
				classification.kinds[repositoryPath]?.contains(.status) != true,
				let target = targets.first(where: { $0.repositoryPath == repositoryPath })
			else {
				continue
			}

			if await containsUnignoredPath(paths, inWorkTree: target.workTree) {
				classification.kinds[repositoryPath, default: []].insert(.status)
			}
		}

		return classification.kinds
			.filter { !$0.value.isEmpty }
			.map { GitRepositoryChange(repositoryPath: $0.key, kinds: $0.value) }
			.sorted { $0.repositoryPath < $1.repositoryPath }
	}

	/// Whether any of `paths` (relative to `workTree`) is one `git status` would report on.
	///
	/// A build writes thousands of files into ignored output folders; asking git which of them
	/// are ignored is one cheap process per batch, where refreshing on each would be a full
	/// `git status` every batch for as long as the build runs. Tracked files are never reported
	/// as ignored, so an edit to one counts even when it matches a pattern. When git cannot
	/// answer, the paths count as changed: a needless refresh beats a missed one.
	static func containsUnignoredPath(_ paths: [String], inWorkTree workTree: String) async -> Bool {
		let unique = Array(Set(paths)).sorted()
		for start in stride(from: 0, to: unique.count, by: checkIgnoreChunkSize) {
			let chunk = Array(unique[start ..< min(start + checkIgnoreChunkSize, unique.count)])
			let result = await ProcessRunner.runGit(
				arguments: ["--no-optional-locks", "check-ignore", "--"] + chunk,
				at: workTree
			)
			switch result.exitCode {
			case 0:
				// Some were ignored; one line per ignored path.
				let ignoredCount = result.outputString.split(separator: "\n").count
				if ignoredCount < chunk.count {
					return true
				}

			case 1:
				// None were ignored.
				return true

			default:
				return true
			}
		}
		return false
	}
}
