import Foundation

/// Result of a process execution with captured output and error streams
public nonisolated struct ProcessResult {
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

		// Continuously read from output pipe in background to prevent buffer overflow
		outputPipe.fileHandleForReading.readabilityHandler = { fileHandle in
			let data = fileHandle.availableData
			outputCollector.append(data)
		}

		// Continuously read from error pipe in background to prevent buffer overflow
		errorPipe.fileHandleForReading.readabilityHandler = { fileHandle in
			let data = fileHandle.availableData
			errorCollector.append(data)
		}

		return await withTaskCancellationHandler {
			await withCheckedContinuation { continuation in
				process.terminationHandler = { proc in
					// Stop reading from pipes
					outputPipe.fileHandleForReading.readabilityHandler = nil
					errorPipe.fileHandleForReading.readabilityHandler = nil

					// Read any remaining data
					let remainingOutput = (try? outputPipe.fileHandleForReading.readToEnd()) ?? Data()
					let remainingError = (try? errorPipe.fileHandleForReading.readToEnd()) ?? Data()

					// Combine all output
					outputCollector.append(remainingOutput)
					errorCollector.append(remainingError)

					let result = ProcessResult(
						exitCode: proc.terminationStatus,
						output: outputCollector.getData(),
						error: errorCollector.getData()
					)

					continuation.resume(returning: result)
				}

				do {
					try process.run()
				}
				catch {
					// If process fails to start, return a failure result
					let result = ProcessResult(
						exitCode: -1,
						output: Data(),
						error: "Failed to start process: \(error.localizedDescription)".data(using: .utf8) ?? Data()
					)
					continuation.resume(returning: result)
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
	private static let resolvedGitExecutable = Task<URL, Never> { @concurrent in
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
		await run(
			executableURL: resolvedGitExecutable.value,
			arguments: arguments,
			currentDirectory: URL(filePath: repositoryPath),
			environment: EnvironmentHelper.setupEnvironment()
		)
	}
}
