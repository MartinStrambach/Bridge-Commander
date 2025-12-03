import AppKit
import Foundation

enum TerminalLauncher {

	/// Opens Terminal.app with a new window at the specified directory
	/// - Parameter path: The directory path to open in Terminal
	static func openTerminal(at path: String) {
		// Escape the path for shell safety
		let escapedPath = path.replacingOccurrences(of: "\"", with: "\\\"")

		let process = Process()
		process.executableURL = URL(filePath: "/usr/bin/open")
		process.arguments = ["-a", "Terminal", escapedPath]
		process.launch()
	}

	/// Alternative method using NSWorkspace (opens terminal but doesn't set directory)
	/// This is kept as a fallback but the AppleScript method is preferred
	static func openTerminalWithWorkspace(at path: String) {
		let url = URL(fileURLWithPath: path)
		NSWorkspace.shared.open(url)
	}
}
