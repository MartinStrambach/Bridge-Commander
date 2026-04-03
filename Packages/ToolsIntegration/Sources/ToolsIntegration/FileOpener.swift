import Foundation
import ProcessExecution

public nonisolated enum FileOpener {

	/// Opens a file in the appropriate IDE based on its extension
	/// - Parameters:
	///   - filePath: Relative path to the file
	///   - repositoryPath: Absolute path to the repository
	///   - xcodeProjectPath: Path to .xcworkspace or .xcodeproj, if available
	public static func openFileInIDE(
		filePath: String,
		repositoryPath: String,
		xcodeProjectPath: String? = nil
	) async throws {
		let fullPath = (repositoryPath as NSString).appendingPathComponent(filePath)
		let fileExtension = (filePath as NSString).pathExtension.lowercased()

		guard FileManager.default.fileExists(atPath: fullPath) else {
			throw FileOpenerError.failedToOpen("File does not exist")
		}

		switch fileExtension {
		case "swift":
			if let xcodeProjectPath {
				try await XcodeProjectGenerator.openProject(at: xcodeProjectPath)
			}
			let result = await ProcessRunner.run(
				executableURL: URL(filePath: "/usr/bin/xed"),
				arguments: [fullPath]
			)
			guard result.success else {
				let errorMsg = result.trimmedError
				throw FileOpenerError
					.failedToOpen(errorMsg.isEmpty ? "Unknown error (exit code \(result.exitCode))" : errorMsg)
			}

		case "kt",
		     "kts":
			try await AndroidStudioLauncher.openInAndroidStudio(at: repositoryPath)
			let result = await ProcessRunner.run(
				executableURL: URL(filePath: "/usr/bin/open"),
				arguments: [fullPath]
			)
			guard result.success else {
				let errorMsg = result.trimmedError
				throw FileOpenerError
					.failedToOpen(errorMsg.isEmpty ? "Unknown error (exit code \(result.exitCode))" : errorMsg)
			}

		default:
			let result = await ProcessRunner.run(
				executableURL: URL(filePath: "/usr/bin/open"),
				arguments: [fullPath]
			)
			guard result.success else {
				let errorMsg = result.trimmedError
				throw FileOpenerError
					.failedToOpen(errorMsg.isEmpty ? "Unknown error (exit code \(result.exitCode))" : errorMsg)
			}
		}
	}
}

// MARK: - Errors

public enum FileOpenerError: Error, LocalizedError {
	case failedToOpen(String)

	public var errorDescription: String? {
		switch self {
		case let .failedToOpen(message):
			"Failed to open file: \(message)"
		}
	}
}
