import AppKit
import Foundation

enum XcodeProjectGenerator {

	/// Generates Xcode project by running ti and tg commands sequentially in the configured iOS subfolder
	/// - Parameters:
	///   - repositoryPath: The repository root path
	///   - iosSubfolderPath: The iOS subfolder path (e.g., "ios/FlashScore")
	///   - onStateChange: Callback invoked when state changes
	/// - Returns: Path to the generated Xcode project/workspace, or throws an error
	@MainActor
	static func generateProject(
		at repositoryPath: String,
		iosSubfolderPath: String,
		onStateChange: @escaping (XcodeProjectState) -> Void
	) async throws -> String {
		// Get iOS subfolder path
		let iosFlashscorePath = XcodeProjectDetector.getIosFlashscorePath(
			in: repositoryPath,
			iosSubfolderPath: iosSubfolderPath
		)

		// Verify iOS subfolder directory exists
		let fileManager = FileManager.default
		var isDirectory: ObjCBool = false
		guard
			fileManager.fileExists(atPath: iosFlashscorePath, isDirectory: &isDirectory),
			isDirectory.boolValue
		else {
			throw ProjectGenerationError.iosSubfolderNotFound(path: iosSubfolderPath)
		}

		// Step 1: Run ti command in iOS subfolder
		onStateChange(.runningTi)
		let installResult = await TuistCommandHelper.runCommand(.install, at: iosFlashscorePath)
		if case let .failure(error) = installResult {
			throw ProjectGenerationError.commandFailed(command: "tuist install", message: error.localizedDescription)
		}

		// Step 2: Run tg command in iOS subfolder
		onStateChange(.runningTg)
		let generateResult = await TuistCommandHelper.runCommand(.generate, at: iosFlashscorePath)
		if case let .failure(error) = generateResult {
			throw ProjectGenerationError.commandFailed(command: "tuist generate", message: error.localizedDescription)
		}

		// Step 3: Find the generated project
		onStateChange(.checking)
		guard let projectPath = XcodeProjectDetector.findXcodeProject(
			in: repositoryPath,
			iosSubfolderPath: iosSubfolderPath
		) else {
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

}

// MARK: - Error Types

enum ProjectGenerationError: LocalizedError {
	case commandFailed(command: String, message: String)
	case projectNotFoundAfterGeneration
	case failedToOpenProject
	case iosSubfolderNotFound(path: String)

	var errorDescription: String? {
		switch self {
		case let .commandFailed(command, message):
			"Command '\(command)' failed: \(message)"
		case .projectNotFoundAfterGeneration:
			"Project not found after generation"
		case .failedToOpenProject:
			"Failed to open Xcode project"
		case let .iosSubfolderNotFound(path):
			"iOS subfolder '\(path)' not found in repository"
		}
	}
}
