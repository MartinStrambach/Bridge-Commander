import Foundation

/// Result of a process execution with captured output and error streams
struct ProcessResult {
	let exitCode: Int32
	let output: Data
	let error: Data

	var outputString: String {
		String(data: output, encoding: .utf8) ?? ""
	}

	var errorString: String {
		String(data: error, encoding: .utf8) ?? ""
	}

	var success: Bool {
		exitCode == 0
	}
}

/// Helper for running shell processes with proper pipe handling to prevent buffer overflow
enum ProcessRunner {

	/// Runs a process and captures its output and error streams
	/// - Parameters:
	///   - executableURL: Path to the executable
	///   - arguments: Command line arguments
	///   - currentDirectory: Working directory (optional)
	///   - environment: Environment variables (optional)
	/// - Returns: ProcessResult containing exit code and captured streams
	static func run(
		executableURL: URL,
		arguments: [String],
		currentDirectory: URL? = nil,
		environment: [String: String]? = nil
	) async -> ProcessResult {
		await withCheckedContinuation { continuation in
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
	}

	/// Convenience method for running git commands
	/// - Parameters:
	///   - arguments: Git command arguments (e.g., ["status", "--short"])
	///   - repositoryPath: Path to the repository
	/// - Returns: ProcessResult containing exit code and captured streams
	static func runGit(
		arguments: [String],
		at repositoryPath: String
	) async -> ProcessResult {
		await run(
			executableURL: URL(filePath: "/usr/bin/git"),
			arguments: arguments,
			currentDirectory: URL(filePath: repositoryPath),
			environment: GitEnvironmentHelper.setupEnvironment()
		)
	}
}
