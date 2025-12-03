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

		try await withCheckedThrowingContinuation { continuation in
			let process = Process()
			process.executableURL = URL(filePath: "/usr/bin/open")
			process.arguments = ["-a", "Android Studio", path]

			let errorPipe = Pipe()
			process.standardError = errorPipe

			process.terminationHandler = { proc in
				// If command succeeded → return normally
				if proc.terminationStatus == 0 {
					continuation.resume()
					return
				}

				// If failed → read stderr and throw
				let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
				let message = String(data: data, encoding: .utf8)?
					.trimmingCharacters(in: .whitespacesAndNewlines)
					?? "Unknown error"

				continuation.resume(throwing: NSError(
					domain: "AndroidStudioLauncher",
					code: Int(proc.terminationStatus),
					userInfo: [NSLocalizedDescriptionKey: message]
				))
			}

			do {
				try process.run()
			}
			catch {
				continuation.resume(throwing: error)
			}
		}
	}
}
