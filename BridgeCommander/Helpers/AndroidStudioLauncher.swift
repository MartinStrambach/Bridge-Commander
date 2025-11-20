import AppKit
import Foundation

enum AndroidStudioLauncher {

	/// Opens Android Studio with the specified repository path
	/// If the project is already open, focuses the existing window instead
	/// - Parameter path: The directory path to open in Android Studio
	static func openInAndroidStudio(at path: String) {
		// Check if the project is already open in Android Studio
		if AndroidStudioDetector.isProjectAlreadyOpen(at: path) {
			// Project is already open, just focus the window
			_ = AndroidStudioDetector.focusProjectWindow(at: path)
			return
		}

		// Use the macOS 'open' command to launch Android Studio
		let process = Process()
		process.launchPath = "/usr/bin/open"
		process.arguments = ["-a", "Android Studio", path]

		let errorPipe = Pipe()
		process.standardError = errorPipe

		do {
			process.launch()
			process.waitUntilExit()

			// Check if the process failed
			if process.terminationStatus != 0 {
				let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
				let errorMessage = String(data: errorData, encoding: .utf8)?
					.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown error"

				// Show error to user
				showError(message: errorMessage, path: path)
			}
		}
		catch {
			// Process launch failed
			showError(message: error.localizedDescription, path: path)
		}
	}

	/// Shows an error alert to the user
	private static func showError(message: String, path: String) {
		let alert = NSAlert()
		alert.messageText = "Failed to Open Android Studio"

		// Provide helpful error message
		if message.contains("does not exist") || message.contains("Unable to find application") {
			alert.informativeText = """
			Android Studio is not installed or cannot be found.

			Please install Android Studio from:
			https://developer.android.com/studio

			Path: \(path)
			"""
		}
		else {
			alert.informativeText = """
			Error: \(message)

			Path: \(path)

			Make sure Android Studio is properly installed and you have permission to open it.
			"""
		}

		alert.alertStyle = .warning
		alert.addButton(withTitle: "OK")
		alert.runModal()
	}
}
