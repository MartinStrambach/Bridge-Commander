import Foundation

nonisolated enum FileOpener {

	/// Opens a file in the appropriate IDE based on its extension
	/// - Parameters:
	///   - filePath: Relative path to the file
	///   - repositoryPath: Absolute path to the repository
	///   - androidStudioPath: Path to Android Studio executable
	static func openFileInIDE(
		filePath: String,
		repositoryPath: String,
		androidStudioPath: String
	) async throws {
		let fullPath = (repositoryPath as NSString).appendingPathComponent(filePath)
		let fileExtension = (filePath as NSString).pathExtension.lowercased()

		// Check if file exists
		guard FileManager.default.fileExists(atPath: fullPath) else {
			throw FileOpenerError.failedToOpen("File does not exist")
		}

		let result: ProcessResult

		switch fileExtension {
		case "swift":
			// For Swift files, use xed command which is specifically for opening in Xcode
			result = await ProcessRunner.run(
				executableURL: URL(filePath: "/usr/bin/xed"),
				arguments: [fullPath]
			)

		case "kt",
		     "kts":
			// For Kotlin files, open in Android Studio within the project context
			// Use Android Studio's command-line launcher to open both project and file
			result = await ProcessRunner.run(
				executableURL: URL(filePath: androidStudioPath),
				arguments: [repositoryPath, fullPath]
			)

		default:
			// For other files, use default application
			result = await ProcessRunner.run(
				executableURL: URL(filePath: "/usr/bin/open"),
				arguments: [fullPath]
			)
		}

		guard result.success else {
			let errorMsg = result.errorString.trimmingCharacters(in: .whitespacesAndNewlines)
			throw FileOpenerError
				.failedToOpen(errorMsg.isEmpty ? "Unknown error (exit code \(result.exitCode))" : errorMsg)
		}
	}
}

// MARK: - Errors

enum FileOpenerError: Error, LocalizedError {
	case failedToOpen(String)

	var errorDescription: String? {
		switch self {
		case let .failedToOpen(message):
			"Failed to open file: \(message)"
		}
	}
}
