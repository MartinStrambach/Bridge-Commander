import Foundation

// MARK: - Tuist Action

enum TuistAction: Equatable {
	case generate
	case install
	case cache
	case edit

	var commandString: String {
		switch self {
		case .generate:
			"generate"
		case .install:
			"install"
		case .cache:
			"cache"
		case .edit:
			"edit"
		}
	}
}

// MARK: - Tuist Command Helper

enum TuistCommandHelper {
	/// Runs a Tuist command using mise exec at the specified repository path
	/// - Parameters:
	///   - action: The Tuist action to run
	///   - path: The repository path where the command should be executed
	///   - shouldOpenXcode: For generate action, controls whether Xcode opens after generation
	/// - Returns: A Result containing the command output on success or an error on failure
	static func runCommand(_ action: TuistAction, at path: String, shouldOpenXcode: Bool) async -> Result<String, Error> {
		await withCheckedContinuation { continuation in
			let process = Process()
			process.currentDirectoryURL = URL(fileURLWithPath: path)
			process.executableURL = URL(fileURLWithPath: "/bin/zsh")
			process.environment = GitEnvironmentHelper.setupEnvironment()

			// Replace 'mise exec' with full path to mise for compatibility in sandbox
			let misePath = NSHomeDirectory() + "/.local/bin/mise"
			let commandString = action.commandString

			// Add --no-open flag for generate action when Xcode should not open
			let flags = (action == .generate && !shouldOpenXcode) ? " --no-open" : ""
			let fullCommand = "\(misePath) exec -- tuist \(commandString)\(flags)"

			process.arguments = ["-c", fullCommand]

			let outputPipe = Pipe()
			let errorPipe = Pipe()
			process.standardOutput = outputPipe
			process.standardError = errorPipe

			process.terminationHandler = { terminatedProcess in
				let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
				let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

				let output = String(data: outputData, encoding: .utf8) ?? ""
				let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

				if terminatedProcess.terminationStatus == 0 {
					continuation.resume(returning: .success(output))
				}
				else {
					let errorMessage = errorOutput
						.isEmpty
						? "Command failed with exit code \(terminatedProcess.terminationStatus)"
						: errorOutput
					let error = NSError(
						domain: "TuistError",
						code: Int(terminatedProcess.terminationStatus),
						userInfo: [NSLocalizedDescriptionKey: errorMessage]
					)
					continuation.resume(returning: .failure(error))
				}
			}

			do {
				try process.run()
			}
			catch {
				continuation.resume(returning: .failure(error))
			}
		}
	}
}
