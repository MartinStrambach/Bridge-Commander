//
//  ClaudeCodeLauncher.swift
//  Bridge Commander
//
//  Helper for launching Claude Code in Terminal at a repository path
//

import Foundation
import AppKit

struct ClaudeCodeLauncher {

    /// Opens Terminal and runs Claude Code at the specified repository path
    /// - Parameter path: The directory path to run Claude Code in
    static func runClaudeCode(at path: String) {
        // Escape single quotes for shell command
//        let escapedPath = path.replacingOccurrences(of: "'", with: "'\\''")

		let appleScript = """
		tell application "Terminal"
			activate
			do script "cd '\(path)' && claude code ."
		end tell
		"""

		let process = Process()
		process.launchPath = "/usr/bin/osascript"
		process.arguments = ["-e", appleScript]
		process.launch()
    }
}
