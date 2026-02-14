import AppKit
import Foundation

nonisolated enum TerminalLauncher {

	/// Opens Terminal.app based on the specified behavior (new tab or new window)
	/// - Parameters:
	///   - path: The directory path to open in Terminal
	///   - behavior: The opening behavior (new tab or new window)
	static func openTerminal(at path: String, behavior: TerminalOpeningBehavior) async {
		switch behavior {
		case .newTab:
			await openTerminalInNewTab(at: path)

		case .newWindow:
			await openTerminalInNewWindow(at: path)
		}
	}

	/// Alternative method using NSWorkspace (opens terminal but doesn't set directory)
	/// This is kept as a fallback but the AppleScript method is preferred
	static func openTerminalWithWorkspace(at path: String) {
		let url = URL(fileURLWithPath: path)
		NSWorkspace.shared.open(url)
	}

	/// Opens Terminal.app with a new tab in existing window (or new window if none exists)
	/// - Parameter path: The directory path to open in Terminal
	private static func openTerminalInNewTab(at path: String) async {
		// Escape the path for AppleScript safety
		let escapedPath = path.replacingOccurrences(of: "\\", with: "\\\\")
			.replacingOccurrences(of: "\"", with: "\\\"")

		// AppleScript that opens a new tab if Terminal has windows, otherwise creates a new window
		let appleScript = """
		tell application "Terminal"
			activate
			if (count of windows) > 0 then
				tell application "System Events"
					tell process "Terminal"
						keystroke "t" using command down
					end tell
				end tell
				delay 0.2
				do script "cd \\"\(escapedPath)\\"" in front window
			else
				do script "cd \\"\(escapedPath)\\""
			end if
		end tell
		"""

		let result = await ProcessRunner.run(
			executableURL: URL(filePath: "/usr/bin/osascript"),
			arguments: ["-e", appleScript]
		)

		if !result.success {
			print("Failed to open Terminal: \(result.errorString)")
		}
	}

	/// Opens Terminal.app with a new window at the specified directory
	/// - Parameter path: The directory path to open in Terminal
	private static func openTerminalInNewWindow(at path: String) async {
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

}
