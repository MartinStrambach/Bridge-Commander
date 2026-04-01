import AppKit
import Foundation
import ProcessExecution

public nonisolated enum TerminalLauncher {

	public static func openTerminal(at path: String, app: TerminalApp, behavior: TerminalOpeningBehavior) async {
		switch app {
		case .systemTerminal:
			if behavior == .newTab {
				await openSystemTerminalInNewTab(at: path)
			} else {
				await openAppInNewWindow(appName: app.appName, at: path)
			}
		case .iTerm2:
			if behavior == .newTab {
				await openITerm2InNewTab(at: path)
			} else {
				await openITerm2InNewWindow(at: path)
			}
		case .ghostty:
			await openAppInNewWindow(appName: app.appName, at: path)
		}
	}

	private static func openSystemTerminalInNewTab(at path: String) async {
		let escapedPath = path
			.replacingOccurrences(of: "\\", with: "\\\\")
			.replacingOccurrences(of: "\"", with: "\\\"")

		let script = """
		if application "Terminal" is not running then
			tell application "Terminal"
				do script "cd \\"\(escapedPath)\\""
				activate
			end tell
		else
			tell application "Terminal"
				activate
				tell application "System Events"
					tell process "Terminal"
						keystroke "t" using command down
					end tell
				end tell
				delay 0.2
				do script "cd \\"\(escapedPath)\\"" in front window
			end tell
		end if
		"""

		let result = await ProcessRunner.run(
			executableURL: URL(filePath: "/usr/bin/osascript"),
			arguments: ["-e", script]
		)

		if !result.success {
			print("Failed to open Terminal: \(result.errorString)")
		}
	}

	private static func openITerm2InNewTab(at path: String) async {
		let escapedPath = path
			.replacingOccurrences(of: "\\", with: "\\\\")
			.replacingOccurrences(of: "\"", with: "\\\"")

		let script = """
		if application "iTerm" is not running then
			tell application "iTerm"
				activate
			end tell
			delay 0.3
			tell application "iTerm"
				tell current session of current window
					write text "cd \\"\(escapedPath)\\""
				end tell
			end tell
		else
			tell application "iTerm"
				if (count of windows) = 0 then
					set newSession to current session of (create window with default profile)
				else
					set newSession to current session of (create tab with default profile of current window)
				end if
				tell newSession
					write text "cd \\"\(escapedPath)\\""
				end tell
				activate
			end tell
		end if
		"""

		let result = await ProcessRunner.run(
			executableURL: URL(filePath: "/usr/bin/osascript"),
			arguments: ["-e", script]
		)

		if !result.success {
			print("Failed to open iTerm2: \(result.errorString)")
		}
	}

	private static func openITerm2InNewWindow(at path: String) async {
		let escapedPath = path
			.replacingOccurrences(of: "\\", with: "\\\\")
			.replacingOccurrences(of: "\"", with: "\\\"")

		let script = """
		if application "iTerm" is not running then
			tell application "iTerm"
				activate
			end tell
			delay 0.3
			tell application "iTerm"
				tell current session of current window
					write text "cd \\"\(escapedPath)\\""
				end tell
			end tell
		else
			tell application "iTerm"
				set newWindow to (create window with default profile)
				tell current session of newWindow
					write text "cd \\"\(escapedPath)\\""
				end tell
				activate
			end tell
		end if
		"""

		let result = await ProcessRunner.run(
			executableURL: URL(filePath: "/usr/bin/osascript"),
			arguments: ["-e", script]
		)

		if !result.success {
			print("Failed to open iTerm2: \(result.errorString)")
		}
	}

	private static func openAppInNewWindow(appName: String, at path: String) async {
		let result = await ProcessRunner.run(
			executableURL: URL(filePath: "/usr/bin/open"),
			arguments: ["-a", appName, path]
		)

		if !result.success {
			print("Failed to open \(appName): \(result.errorString)")
		}
	}

}
