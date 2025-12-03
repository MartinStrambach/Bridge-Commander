import AppKit
import Foundation

enum ClaudeCodeLauncher {

	/// Opens Terminal and runs Claude Code at the specified repository path
	/// - Parameter path: The directory path to run Claude Code in
	static func runClaudeCode(at path: String) throws {
		let appleScript = """
		tell application "Terminal"
			activate
			do script "cd '\(path)' && claude"
		end tell
		"""

		let process = Process()
		process.executableURL = URL(filePath: "/usr/bin/osascript")
		process.arguments = ["-e", appleScript]
		try process.run()
	}
}
