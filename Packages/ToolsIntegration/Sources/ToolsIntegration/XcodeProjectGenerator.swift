import AppKit
import Foundation
import ProcessExecution

public nonisolated enum XcodeProjectGenerator {

	/// Generates the Xcode project in the configured iOS subfolder: `tuist install` then
	/// `tuist generate` for Tuist, `xcodegen generate` for XcodeGen
	/// - Parameters:
	///   - repositoryPath: The repository root path
	///   - iosSubfolderPath: The iOS subfolder path (e.g., "ios/MyApp")
	///   - generator: The tool whose manifest the subfolder holds
	///   - shouldOpenXcode: Controls whether Tuist opens Xcode after generation (XcodeGen never does)
	///   - runMode: How the generator's CLI is started
	///   - onStateChange: Awaited on every state change, so a caller that forwards the state
	///     sees each one before the next — and before this function returns
	/// - Returns: Path to the generated Xcode project/workspace, or throws an error
	public static func generateProject(
		at repositoryPath: String,
		iosSubfolderPath: String,
		generator: ProjectGenerator,
		shouldOpenXcode: Bool,
		misePath: String,
		runMode: GeneratorRunMode,
		onStateChange: @Sendable (XcodeProjectState) async -> Void
	) async throws -> String {
		// Get iOS subfolder path
		let iosFolderPath = XcodeProjectDetector.iosFolderPath(
			in: repositoryPath,
			iosSubfolderPath: iosSubfolderPath
		)

		// Verify iOS subfolder directory exists
		let fileManager = FileManager.default
		var isDirectory: ObjCBool = false
		guard
			fileManager.fileExists(atPath: iosFolderPath, isDirectory: &isDirectory),
			isDirectory.boolValue
		else {
			throw ProjectGenerationError.iosSubfolderNotFound(path: iosSubfolderPath)
		}

		switch generator {
		case .tuist:
			try await generateWithTuist(
				at: iosFolderPath,
				shouldOpenXcode: shouldOpenXcode,
				misePath: misePath,
				runMode: runMode,
				onStateChange: onStateChange
			)

		case .xcodeGen:
			await onStateChange(.runningTg)
			let result = await XcodeGenCommandHelper.runCommand(
				.generate,
				at: iosFolderPath,
				misePath: misePath,
				runMode: runMode
			)
			if case let .failure(error) = result {
				throw ProjectGenerationError.commandFailed(command: "xcodegen generate", message: error.localizedDescription)
			}
		}

		// Find the generated project
		await onStateChange(.checking)
		guard
			let projectPath = XcodeProjectDetector.findXcodeProject(
				in: repositoryPath,
				iosSubfolderPath: iosSubfolderPath
			)
		else {
			throw ProjectGenerationError.projectNotFoundAfterGeneration
		}

		return projectPath
	}

	/// Runs `tuist install` then `tuist generate` in the iOS folder.
	private static func generateWithTuist(
		at iosFolderPath: String,
		shouldOpenXcode: Bool,
		misePath: String,
		runMode: GeneratorRunMode,
		onStateChange: @Sendable (XcodeProjectState) async -> Void
	) async throws {
		await onStateChange(.runningTi)
		let installResult = await TuistCommandHelper.runCommand(
			.install,
			at: iosFolderPath,
			shouldOpenXcode: shouldOpenXcode,
			misePath: misePath,
			runMode: runMode
		)
		if case let .failure(error) = installResult {
			throw ProjectGenerationError.commandFailed(command: "tuist install", message: error.localizedDescription)
		}

		await onStateChange(.runningTg)
		let generateResult = await TuistCommandHelper.runCommand(
			.generate,
			at: iosFolderPath,
			shouldOpenXcode: shouldOpenXcode,
			misePath: misePath,
			runMode: runMode
		)
		if case let .failure(error) = generateResult {
			throw ProjectGenerationError.commandFailed(command: "tuist generate", message: error.localizedDescription)
		}
	}

	/// Opens the Xcode project at the specified path
	/// - Parameter projectPath: Full path to .xcworkspace or .xcodeproj
	public static func openProject(at projectPath: String) async throws {
		let result = await ProcessRunner.run(
			executableURL: URL(filePath: "/usr/bin/open"),
			arguments: [projectPath]
		)

		guard result.success else {
			throw ProjectGenerationError.failedToOpenProject
		}
	}

}

// MARK: - Error Types

public enum ProjectGenerationError: LocalizedError {
	case commandFailed(command: String, message: String)
	case projectNotFoundAfterGeneration
	case failedToOpenProject
	case iosSubfolderNotFound(path: String)

	public var errorDescription: String? {
		switch self {
		case let .commandFailed(command, message):
			"Command '\(command)' failed: \(message)"
		case .projectNotFoundAfterGeneration:
			"Project not found after generation"
		case .failedToOpenProject:
			"Failed to open Xcode project"
		case let .iosSubfolderNotFound(path):
			"Xcode project path '\(path)' not found in repository"
		}
	}
}
