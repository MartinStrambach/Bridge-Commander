import AppKit
import Foundation
import ProcessExecution

public nonisolated enum AndroidStudioLauncher {

	/// Opens Android Studio with the specified repository path
	/// If the project is already open, focuses the existing window instead
	/// - Parameter path: The directory path to open in Android Studio
	public static func openInAndroidStudio(at path: String) async throws {
		try await openProject(at: path, in: "Android Studio", bundleIdentifier: AndroidStudioDetector.bundleIdentifier)
	}

	/// Opens a project directory in Android Studio or another JetBrains IDE, focusing its window
	/// instead when the project is already open
	/// - Parameters:
	///   - path: The directory path to open
	///   - application: The IDE's name or path, as `open -a` takes it
	///   - bundleIdentifier: The IDE's bundle identifier, to find an already open window
	static func openProject(at path: String, in application: String, bundleIdentifier: String) async throws {
		// If already open → just focus and return
		if AndroidStudioDetector.isProjectAlreadyOpen(at: path, bundleIdentifier: bundleIdentifier) {
			_ = AndroidStudioDetector.focusProjectWindow(at: path, bundleIdentifier: bundleIdentifier)
			return
		}

		let result = await ProcessRunner.run(
			executableURL: URL(filePath: "/usr/bin/open"),
			arguments: ["-a", application, path]
		)

		guard result.success else {
			let message = result.trimmedError
			throw NSError(
				domain: "AndroidStudioLauncher",
				code: Int(result.exitCode),
				userInfo: [NSLocalizedDescriptionKey: message.isEmpty ? "Unknown error" : message]
			)
		}
	}
}
