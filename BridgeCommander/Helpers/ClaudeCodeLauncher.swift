import AppKit
import Foundation

enum ClaudeCodeLauncher {

	/// Opens Terminal and runs Claude Code at the specified repository path
	/// - Parameter path: The directory path to run Claude Code in
	static func runClaudeCode(at path: String) async throws {
		let appleScript = """
		tell application "Terminal"
			activate
			do script "cd '\(path)' && claude"
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
