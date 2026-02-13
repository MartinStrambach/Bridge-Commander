import AppKit
import Foundation

nonisolated enum TerminalLauncher {

	/// Opens Terminal.app with a new window at the specified directory
	/// - Parameter path: The directory path to open in Terminal
	static func openTerminal(at path: String) async {
		// Escape the path for shell safety
		let escapedPath = path.replacingOccurrences(of: "\"", with: "\\\"")

		let result = await ProcessRunner.run(
			executableURL: URL(filePath: "/usr/bin/open"),
			arguments: ["-a", "Terminal", escapedPath]
		)

		if !result.success {
			print("Failed to open Terminal: \(result.errorString)")
		}
	}

	/// Alternative method using NSWorkspace (opens terminal but doesn't set directory)
	/// This is kept as a fallback but the AppleScript method is preferred
	static func openTerminalWithWorkspace(at path: String) {
		let url = URL(fileURLWithPath: path)
		NSWorkspace.shared.open(url)
	}
}
