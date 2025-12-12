import AppKit
import Foundation

enum XcodeProjectGenerator {

	/// Generates Xcode project by running ti and tg commands sequentially in ios/Flashscore
	/// - Parameters:
	///   - repositoryPath: The repository root path
	///   - onStateChange: Callback invoked when state changes
	/// - Returns: Path to the generated Xcode project/workspace, or throws an error
	@MainActor
	static func generateProject(
		at repositoryPath: String,
		onStateChange: @escaping (XcodeProjectState) -> Void
	) async throws -> String {
		// Get ios/Flashscore subfolder path
		let iosFlashscorePath = XcodeProjectDetector.getIosFlashscorePath(in: repositoryPath)

		// Verify ios/Flashscore directory exists
		let fileManager = FileManager.default
		var isDirectory: ObjCBool = false
		guard
			fileManager.fileExists(atPath: iosFlashscorePath, isDirectory: &isDirectory),
			isDirectory.boolValue
		else {
			throw ProjectGenerationError.iosFlashscoreFolderNotFound
		}

		// Step 1: Run ti command in ios/Flashscore
		onStateChange(.runningTi)
		try await runCommand("mise exec -- tuist install", at: iosFlashscorePath)

		// Step 2: Run tg command in ios/Flashscore
		onStateChange(.runningTg)
		try await runCommand("mise exec -- tuist generate", at: iosFlashscorePath)

		// Step 3: Find the generated project
		onStateChange(.checking)
		guard let projectPath = XcodeProjectDetector.findXcodeProject(in: repositoryPath) else {
			throw ProjectGenerationError.projectNotFoundAfterGeneration
		}

		return projectPath
	}

	/// Opens the Xcode project at the specified path
	/// - Parameter projectPath: Full path to .xcworkspace or .xcodeproj
	static func openProject(at projectPath: String) throws {
		let process = Process()
		process.executableURL = URL(filePath: "/usr/bin/open")
		process.arguments = [projectPath]

		process.launch()
		process.waitUntilExit()

		if process.terminationStatus != 0 {
			throw ProjectGenerationError.failedToOpenProject
		}
	}

	// MARK: - Private Helpers

	/// Runs a shell command at the specified path
	private static func runCommand(_ command: String, at path: String) async throws {
		try await withCheckedThrowingContinuation { continuation in
			let process = Process()
			process.currentDirectoryPath = path
			process.executableURL = URL(fileURLWithPath: "/bin/zsh")
			process.environment = GitEnvironmentHelper.setupEnvironment()

			// Replace 'mise exec' with full path to mise for compatibility in sandbox
			let misePath = NSHomeDirectory() + "/.local/bin/mise"
			let expandedCommand = command.replacingOccurrences(of: "mise exec", with: "\(misePath) exec")

			process.arguments = ["-c", expandedCommand]

			let pipe = Pipe()
			let errorPipe = Pipe()
			process.standardOutput = pipe
			process.standardError = errorPipe

			process.terminationHandler = { process in
				if process.terminationStatus == 0 {
					continuation.resume()
				}
				else {
					let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
					let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
					continuation.resume(throwing: ProjectGenerationError.commandFailed(
						command: command,
						message: errorMessage
					))
				}
			}

			do {
				try process.run()
			}
			catch {
				continuation.resume(throwing: ProjectGenerationError.commandFailed(
					command: command,
					message: error.localizedDescription
				))
			}
		}
	}
}

// MARK: - Error Types

enum ProjectGenerationError: LocalizedError {
	case commandFailed(command: String, message: String)
	case projectNotFoundAfterGeneration
	case failedToOpenProject
	case iosFlashscoreFolderNotFound

	var errorDescription: String? {
		switch self {
		case let .commandFailed(command, message):
			"Command '\(command)' failed: \(message)"
		case .projectNotFoundAfterGeneration:
			"Project not found after generation"
		case .failedToOpenProject:
			"Failed to open Xcode project"
		case .iosFlashscoreFolderNotFound:
			"ios/Flashscore folder not found in repository"
		}
	}
}
