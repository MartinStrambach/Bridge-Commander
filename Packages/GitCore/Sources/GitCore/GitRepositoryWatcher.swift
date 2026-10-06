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

	/// How often a watch that does not cover every repository tries again: a path that was not a
	/// repository yet (a `git worktree add` still writing its `.git` file when the scan listed it),
	/// or a stream FSEvents refused. The caller restarts the watch only when its rows change, so
	/// without this such a row would stay unwatched until then.
	static let retryInterval: Duration = .seconds(30)

	/// Runs until the stream is dropped, never finishing by itself: a watch that cannot start, or
	/// cannot cover every repository, keeps trying every `retryInterval`.
	static func changes(
		repositoryPaths: [String],
		retryInterval: Duration = GitRepositoryWatcher.retryInterval
	) -> AsyncStream<[GitRepositoryChange]> {
		AsyncStream { continuation in
			let task = Task {
				while !Task.isCancelled {
					let targets = resolveTargets(repositoryPaths)
					let didStart = await watch(
						targets,
						recheckingEvery: targets.count < repositoryPaths.count ? retryInterval : nil,
						of: repositoryPaths,
						into: continuation
					)
					if !didStart {
						try? await Task.sleep(for: retryInterval)
					}
				}
				continuation.finish()
			}
			continuation.onTermination = { _ in
				task.cancel()
			}
		}
	}

	private static func resolveTargets(_ repositoryPaths: [String]) -> [GitWatchTarget] {
		repositoryPaths.compactMap(GitWatchTarget.init(repositoryPath:))
	}

	/// Watches `targets` until the task is cancelled or, when `recheckInterval` is set, until
	/// `repositoryPaths` resolve to a different set of targets.
	///
	/// - Returns: Whether the stream started; when not, it returns at once.
	private static func watch(
		_ targets: [GitWatchTarget],
		recheckingEvery recheckInterval: Duration?,
		of repositoryPaths: [String],
		into continuation: AsyncStream<[GitRepositoryChange]>.Continuation
	) async -> Bool {
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
			return false
		}

		defer { stream.stop() }
		guard stream.start() else {
			return false
		}

		await withTaskGroup(of: Void.self) { group in
			if let recheckInterval {
				group.addTask {
					// Ending the batches ends the watch below, and the caller starts a new one.
					while (try? await Task.sleep(for: recheckInterval)) != nil {
						if resolveTargets(repositoryPaths) != targets {
							batchContinuation.finish()
							return
						}
					}
				}
			}

			// One batch at a time, in arrival order: handling one may wait on `git check-ignore`.
			// Iteration also ends when the task is cancelled.
			for await batch in batches {
				let changes = await changes(in: batch, targets: targets)
				if !changes.isEmpty {
					continuation.yield(changes)
				}
			}
			group.cancelAll()
		}
		return true
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
