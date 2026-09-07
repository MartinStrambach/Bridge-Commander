import AppKit
import Foundation
import ProcessExecution

public enum TerminalLauncherError: LocalizedError {
	case failed(String)

	public var errorDescription: String? {
		switch self {
		case let .failed(message): message
		}
	}
}

public nonisolated enum TerminalLauncher {

	public static func openTerminal(
		at path: String,
		app: TerminalApp,
		behavior: TerminalOpeningBehavior,
		command: String? = nil
	) async throws {
		switch app {
		case .systemTerminal:
			try await openSystemTerminal(at: path, command: command, newTab: behavior == .newTab)

		case .iTerm2:
			if behavior == .newTab {
				try await openITerm2InNewTab(at: path, command: command)
			}
			else {
				try await openITerm2InNewWindow(at: path, command: command)
			}

		case .ghostty:
			try await openAppInNewWindow(appName: app.appName, at: path)

		case .warp:
			if behavior == .newTab {
				try await openWarp(at: path, action: "new_tab")
			}
			else {
				try await openWarp(at: path, action: "new_window")
			}
		}
	}

	/// Terminal opens a window at the user's home directory as soon as it launches. A plain
	/// `do script` (no target) always makes *another* window, so launching Terminal cold used to
	/// leave two windows behind: the startup one at home plus the requested one. Both behaviors
	/// therefore reuse the startup window when Terminal was not already running, and only ask for
	/// a fresh tab/window when there was a session to add to.
	private static func openSystemTerminal(at path: String, command: String?, newTab: Bool) async throws {
		let commandLiteral = appleScriptLiteral(shellCommand(at: path, command: command))

		// Terminal's scripting dictionary cannot make a tab, so a new tab means driving ⌘T through
		// System Events. That is asynchronous, so wait for the front window's selected tab to
		// actually change rather than guessing a delay — otherwise the command lands in the tab
		// that was already there. Depending on Terminal's profile and tabbing settings ⌘T may open
		// a window instead of a tab; either way the front window's selected tab is the fresh one.
		//
		// The keystroke must stay inside a `try`: without Accessibility permission System Events
		// *errors* ("osascript is not allowed to send keystrokes") rather than doing nothing, which
		// aborted the whole script and opened no terminal at all. Degrade to a plain `do script` —
		// the user gets a window instead of a tab, and the list's Accessibility banner explains
		// why. That is also better than typing into a tab that may have something running in it.
		let alreadyRunningBranch =
			newTab
			? """
					set previousTTY to tty of selected tab of front window
					repeat 20 times
						if frontmost then exit repeat
						delay 0.05
					end repeat
					set hasFreshTab to false
					try
						tell application "System Events"
							tell process "Terminal"
								keystroke "t" using command down
							end tell
						end tell
						repeat 40 times
							if (count of windows) > 0 and tty of selected tab of front window is not previousTTY then
								set hasFreshTab to true
								exit repeat
							end if
							delay 0.05
						end repeat
					end try
					if hasFreshTab then
						do script \(commandLiteral) in front window
					else
						do script \(commandLiteral)
					end if
			"""
			: """
					do script \(commandLiteral)
			"""

		let script = """
		set wasRunning to application "Terminal" is running
		tell application "Terminal"
			activate
			if not wasRunning then
				repeat 50 times
					if (count of windows) > 0 then exit repeat
					delay 0.1
				end repeat
			end if
			if (count of windows) = 0 then
				do script \(commandLiteral)
			else if not wasRunning then
				do script \(commandLiteral) in front window
			else
		\(alreadyRunningBranch)
			end if
		end tell
		"""

		let result = await ProcessRunner.run(
			executableURL: URL(filePath: "/usr/bin/osascript"),
			arguments: ["-e", script]
		)

		if !result.success {
			throw TerminalLauncherError.failed(result.errorString)
		}
	}

	/// A `cd` into `path`, optionally chained with `command`, safe to hand to a shell.
	internal static func shellCommand(at path: String, command: String?) -> String {
		let quotedPath = "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"

		guard let command, !command.isEmpty else {
			return "cd \(quotedPath)"
		}

		return "cd \(quotedPath) && \(command)"
	}

	/// Wraps `text` in a quoted AppleScript string literal.
	internal static func appleScriptLiteral(_ text: String) -> String {
		let escaped = text
			.replacingOccurrences(of: "\\", with: "\\\\")
			.replacingOccurrences(of: "\"", with: "\\\"")

		return "\"\(escaped)\""
	}

	private static func openITerm2InNewTab(at path: String, command: String?) async throws {
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
					write text "cd \\"\(escapedPath)\\" && '\(command ?? ":")'"
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
					write text "cd \\"\(escapedPath)\\" && '\(command ?? ":")'"
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
			throw TerminalLauncherError.failed(result.errorString)
		}
	}

	private static func openITerm2InNewWindow(at path: String, command: String?) async throws {
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
					write text "cd \\"\(escapedPath)\\" && '\(command ?? ":")'"
				end tell
			end tell
		else
			tell application "iTerm"
				set newWindow to (create window with default profile)
				tell current session of newWindow
					write text "cd \\"\(escapedPath)\\" && '\(command ?? ":")'"
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
			throw TerminalLauncherError.failed(result.errorString)
		}
	}

	private static func openWarp(at path: String, action: String) async throws {
		guard
			let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
			let url = URL(string: "warp://action/\(action)?path=\(encodedPath)")
		else {
			return
		}

		let result = await ProcessRunner.run(
			executableURL: URL(filePath: "/usr/bin/open"),
			arguments: [url.absoluteString]
		)

		if !result.success {
			throw TerminalLauncherError.failed(result.errorString)
		}
	}

	private static func openAppInNewWindow(appName: String, at path: String) async throws {
		let result = await ProcessRunner.run(
			executableURL: URL(filePath: "/usr/bin/open"),
			arguments: ["-a", appName, path]
		)

		if !result.success {
			throw TerminalLauncherError.failed(result.errorString)
		}
	}

}
