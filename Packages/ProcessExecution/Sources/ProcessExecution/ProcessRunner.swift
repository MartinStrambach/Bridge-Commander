import Foundation
import Synchronization

/// Result of a process execution with captured output and error streams
public nonisolated struct ProcessResult: Sendable {
	public let exitCode: Int32
	public let output: Data
	public let error: Data

	public var outputString: String {
		String(data: output, encoding: .utf8) ?? ""
	}

	public var errorString: String {
		String(data: error, encoding: .utf8) ?? ""
	}

	public var success: Bool {
		exitCode == 0
	}
}

public nonisolated extension ProcessResult {
	/// Returns the output string trimmed of whitespace and newlines
	var trimmedOutput: String {
		outputString.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	/// Returns the error string trimmed of whitespace and newlines
	var trimmedError: String {
		errorString.trimmingCharacters(in: .whitespacesAndNewlines)
	}
}

/// Helper for running shell processes with proper pipe handling to prevent buffer overflow
public nonisolated enum ProcessRunner {

	/// Runs a process and captures its output and error streams
	/// - Parameters:
	///   - executableURL: Path to the executable
	///   - arguments: Command line arguments
	///   - currentDirectory: Working directory (optional)
	///   - environment: Environment variables (optional)
	/// - Returns: ProcessResult containing exit code and captured streams
	public static func run(
		executableURL: URL,
		arguments: [String],
		currentDirectory: URL? = nil,
		environment: [String: String]? = nil
	) async -> ProcessResult {
		let process = Process()
		process.executableURL = executableURL
		process.arguments = arguments

		if let currentDirectory {
			process.currentDirectoryURL = currentDirectory
		}

		if let environment {
			process.environment = environment
		}

		let outputPipe = Pipe()
		let errorPipe = Pipe()
		process.standardOutput = outputPipe
		process.standardError = errorPipe

		let outputCollector = PipeDataCollector()
		let errorCollector = PipeDataCollector()
		let completion = ProcessCompletion(output: outputCollector, error: errorCollector)

		// Each pipe is read as data arrives, so a chatty process never fills its buffer and blocks.
		// A handle's handler calls run one at a time, in order, so the empty read that marks end of
		// file comes after every chunk before it has been appended.
		for (pipe, collector) in [(outputPipe, outputCollector), (errorPipe, errorCollector)] {
			pipe.fileHandleForReading.readabilityHandler = { fileHandle in
				let data = fileHandle.availableData
				guard !data.isEmpty else {
					fileHandle.readabilityHandler = nil
					try? fileHandle.close()
					completion.pipeReachedEndOfFile()
					return
				}

				collector.append(data)
			}
		}

		return await withTaskCancellationHandler {
			await withCheckedContinuation { continuation in
				completion.resume(with: continuation)

				// The result waits for both pipes' end of file as well as the exit. Building it on
				// exit, as this used to, raced a handler that had already read the last chunk but not
				// appended it yet: under load a `git status` succeeded with empty output (a row lost
				// its changes and showed "No remote"), and longer output lost a chunk from the middle.
				process.terminationHandler = { proc in
					completion.processExited(with: proc.terminationStatus)
				}

				do {
					try process.run()
				}
				catch {
					// A launch that fails (e.g. the working directory of a just-deleted worktree is gone)
					// never reaches the termination handler, and the never-launched process keeps both
					// pipes alive. Left open, every failed launch leaked six descriptors until the app hit
					// launchd's limit of 256; from then on `Pipe()` silently hands out fd 0 and every
					// launch fails with "Bad file descriptor".
					process.terminationHandler = nil
					for pipe in [outputPipe, errorPipe] {
						pipe.fileHandleForReading.readabilityHandler = nil
						try? pipe.fileHandleForReading.close()
						try? pipe.fileHandleForWriting.close()
					}

					completion.launchFailed(with: ProcessResult(
						exitCode: -1,
						output: Data(),
						error: "Failed to start process: \(error.localizedDescription)".data(using: .utf8) ?? Data()
					))
				}
			}
		} onCancel: {
			// When the Swift task is cancelled, terminate the process immediately.
			// Without this, the process runs to completion as an orphan, competing
			// with subsequent scans for system resources and causing git failures.
			guard process.isRunning else {
				return
			}

			process.terminate()
		}
	}

	/// `/usr/bin/git` is Apple's xcode-select shim, which re-resolves the active developer
	/// directory on every invocation (~5ms per call). The app spawns dozens of git processes
	/// per refresh, so the binary the shim points at is resolved once and used directly.
	/// Falls back to the shim if resolution fails (e.g., no Xcode/CLT installed).
	///
	/// The resolved binary lives inside an Xcode, which an update can delete or rename under the
	/// running app (Xcodes.app replaces one release candidate with the next). It is resolved again
	/// once it is gone; kept forever, every git call failed to launch until the app restarted —
	/// rows stopped updating, ⌘R did nothing and a deleted worktree's row stayed.
	private static let resolvedGitExecutable = ResolvedExecutable {
		let fallback = URL(filePath: "/usr/bin/git")
		let result = await run(
			executableURL: URL(filePath: "/usr/bin/xcrun"),
			arguments: ["--find", "git"]
		)
		let path = result.trimmedOutput
		guard result.success, !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) else {
			return fallback
		}

		return URL(filePath: path)
	}

	/// Convenience method for running git commands
	/// - Parameters:
	///   - arguments: Git command arguments (e.g., ["status", "--short"])
	///   - repositoryPath: Path to the repository
	/// - Returns: ProcessResult containing exit code and captured streams
	public static func runGit(
		arguments: [String],
		at repositoryPath: String
	) async -> ProcessResult {
		let start = ContinuousClock.now
		let result = await run(
			executableURL: resolvedGitExecutable.url,
			arguments: arguments,
			currentDirectory: URL(filePath: repositoryPath),
			environment: EnvironmentHelper.setupEnvironment()
		)
		GitCommandLog.record(
			arguments: arguments,
			repositoryPath: repositoryPath,
			result: result,
			duration: ContinuousClock.now - start
		)
		return result
	}
}

/// An executable's path, resolved once and reused for as long as the file is still there.
/// Concurrent callers share one resolution, so a launch-time burst of git calls runs `xcrun`
/// once rather than once per call.
nonisolated final class ResolvedExecutable: Sendable {
	private let resolve: @Sendable () async -> URL
	private let resolution: Mutex<Task<URL, Never>>

	init(resolve: @escaping @Sendable () async -> URL) {
		self.resolve = resolve
		resolution = Mutex(Task(operation: resolve))
	}

	var url: URL {
		get async {
			let current = resolution.withLock { $0 }
			let url = await current.value
			if FileManager.default.isExecutableFile(atPath: url.path) {
				return url
			}

			// Only the first caller to find it gone starts a new resolution; the rest await it.
			let replacement = resolution.withLock { task in
				if task == current {
					task = Task(operation: resolve)
				}
				return task
			}
			return await replacement.value
		}
	}
}

/// Resumes a `ProcessRunner.run` call once, when the process has exited and both of its pipes have
/// reached end of file.
nonisolated final class ProcessCompletion: Sendable {
	private struct State {
		var continuation: CheckedContinuation<ProcessResult, Never>?
		var exitCode: Int32?
		var openPipes = 2
	}

	private let output: PipeDataCollector
	private let error: PipeDataCollector
	private let state = Mutex(State())

	init(output: PipeDataCollector, error: PipeDataCollector) {
		self.output = output
		self.error = error
	}

	func resume(with continuation: CheckedContinuation<ProcessResult, Never>) {
		state.withLock { $0.continuation = continuation }
	}

	func pipeReachedEndOfFile() {
		finish { state in
			state.openPipes -= 1
			return state.openPipes == 0 && state.exitCode != nil
		}
	}

	func processExited(with exitCode: Int32) {
		finish { state in
			state.exitCode = exitCode
			return state.openPipes == 0
		}
	}

	func launchFailed(with result: ProcessResult) {
		let continuation = state.withLock { state in
			defer { state.continuation = nil }
			return state.continuation
		}
		continuation?.resume(returning: result)
	}

	/// Applies `update` and resumes when it reports the call is complete — only the first time.
	private func finish(_ update: (inout State) -> Bool) {
		let ready: (CheckedContinuation<ProcessResult, Never>, Int32)? = state.withLock { state in
			guard update(&state), let continuation = state.continuation, let exitCode = state.exitCode else {
				return nil
			}

			state.continuation = nil
			return (continuation, exitCode)
		}
		guard let (continuation, exitCode) = ready else {
			return
		}

		continuation.resume(returning: ProcessResult(
			exitCode: exitCode,
			output: output.getData(),
			error: error.getData()
		))
	}
}
