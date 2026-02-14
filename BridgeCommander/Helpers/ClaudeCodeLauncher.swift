import AppKit
import Foundation

nonisolated enum ClaudeCodeLauncher {

	/// Opens Terminal and runs Claude Code at the specified repository path
	/// - Parameters:
	///   - path: The directory path to run Claude Code in
	///   - behavior: The opening behavior (new tab or new window)
	static func runClaudeCode(at path: String, behavior: TerminalOpeningBehavior) async throws {
		switch behavior {
		case .newTab:
			try await runClaudeCodeInNewTab(at: path)

		case .newWindow:
			try await runClaudeCodeInNewWindow(at: path)
		}
	}

	/// Opens Terminal and runs Claude Code in a new tab (or new window if none exists)
	/// - Parameter path: The directory path to run Claude Code in
	private static func runClaudeCodeInNewTab(at path: String) async throws {
		// Escape the path for AppleScript safety
		let escapedPath = path.replacingOccurrences(of: "\\", with: "\\\\")
			.replacingOccurrences(of: "'", with: "\\'")

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
				do script "cd '\(escapedPath)' && claude" in front window
			else
				do script "cd '\(escapedPath)' && claude"
			end if
		end tell
		"""

		let result = await ProcessRunner.run(
			executableURL: URL(filePath: "/usr/bin/osascript"),
			arguments: ["-e", appleScript]
		)

		guard result.success else {
			let message = result.errorString.trimmingCharacters(in: .whitespacesAndNewlines)
			throw NSError(
				domain: "ClaudeCodeLauncher",
				code: Int(result.exitCode),
				userInfo: [NSLocalizedDescriptionKey: message.isEmpty ? "Failed to launch Claude Code" : message]
			)
		}
	}

	/// Opens Terminal and runs Claude Code in a new window
	/// - Parameter path: The directory path to run Claude Code in
	private static func runClaudeCodeInNewWindow(at path: String) async throws {
		// Escape the path for AppleScript safety
		let escapedPath = path.replacingOccurrences(of: "\\", with: "\\\\")
			.replacingOccurrences(of: "'", with: "\\'")

		let appleScript = """
		tell application "Terminal"
			activate
			do script "cd '\(escapedPath)' && claude"
		end tell
		"""

		let result = await ProcessRunner.run(
			executableURL: URL(filePath: "/usr/bin/osascript"),
			arguments: ["-e", appleScript]
		)

		guard result.success else {
			let message = result.errorString.trimmingCharacters(in: .whitespacesAndNewlines)
			throw NSError(
				domain: "ClaudeCodeLauncher",
				code: Int(result.exitCode),
				userInfo: [NSLocalizedDescriptionKey: message.isEmpty ? "Failed to launch Claude Code" : message]
			)
		}
	}
}
