import AppKit
import Foundation

enum AndroidStudioLauncher {

	/// Opens Android Studio with the specified repository path
	/// If the project is already open, focuses the existing window instead
	/// - Parameter path: The directory path to open in Android Studio
	static func openInAndroidStudio(at path: String) async throws {
		// If already open → just focus and return
		if AndroidStudioDetector.isProjectAlreadyOpen(at: path) {
			_ = AndroidStudioDetector.focusProjectWindow(at: path)
			return
		}

		let result = await ProcessRunner.run(
			executableURL: URL(filePath: "/usr/bin/open"),
			arguments: ["-a", "Android Studio", path]
		)

		guard result.success else {
			let message = result.errorString.trimmingCharacters(in: .whitespacesAndNewlines)
			throw NSError(
				domain: "AndroidStudioLauncher",
				code: Int(result.exitCode),
				userInfo: [NSLocalizedDescriptionKey: message.isEmpty ? "Unknown error" : message]
			)
		}
	}
}
