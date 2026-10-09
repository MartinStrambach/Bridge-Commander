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
		try await openFileInIDE(
			atPath: (repositoryPath as NSString).appendingPathComponent(filePath),
			repositoryPath: repositoryPath,
			xcodeProjectPath: xcodeProjectPath
		)
	}

	/// Opens a file in the appropriate IDE based on its extension
	/// - Parameters:
	///   - fullPath: Absolute path to the file, which need not lie inside the repository
	///   - line: The line to put the cursor on. Only Xcode is given it: `open` has no way to pass one
	///   - repositoryPath: Absolute path to the repository whose IDE project opens alongside
	///   - xcodeProjectPath: Path to .xcworkspace or .xcodeproj, if available
	public static func openFileInIDE(
		atPath fullPath: String,
		line: Int? = nil,
		repositoryPath: String,
		xcodeProjectPath: String? = nil
	) async throws {
		let fileExtension = (fullPath as NSString).pathExtension.lowercased()

		guard FileManager.default.fileExists(atPath: fullPath) else {
			throw FileOpenerError.failedToOpen("File does not exist")
		}

		switch fileExtension {
		case "swift":
			if let xcodeProjectPath {
				try await XcodeProjectGenerator.openProject(at: xcodeProjectPath)
			}
			let lineArguments = line.map { ["--line", String($0)] } ?? []
			try await run("/usr/bin/xed", arguments: lineArguments + [fullPath])

		case "kt",
		     "kts":
			try await AndroidStudioLauncher.openInAndroidStudio(at: repositoryPath)
			try await run("/usr/bin/open", arguments: [fullPath])

		default:
			try await run("/usr/bin/open", arguments: [fullPath])
		}
	}

	private static func run(_ executablePath: String, arguments: [String]) async throws {
		let result = await ProcessRunner.run(
			executableURL: URL(filePath: executablePath),
			arguments: arguments
		)
		guard result.success else {
			let errorMsg = result.trimmedError
			throw FileOpenerError
				.failedToOpen(errorMsg.isEmpty ? "Unknown error (exit code \(result.exitCode))" : errorMsg)
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
