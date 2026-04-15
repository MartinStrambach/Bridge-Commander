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
			if behavior == .newTab {
				try await openSystemTerminalInNewTab(at: path, command: command)
			}
			else {
				try await openSystemTerminalInNewWindow(at: path, command: command)
			}

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

	private static func openSystemTerminalInNewTab(at path: String, command: String?) async throws {
		let escapedPath = path
			.replacingOccurrences(of: "\\", with: "\\\\")
			.replacingOccurrences(of: "\"", with: "\\\"")

		let script = """
		if application "Terminal" is not running then
			tell application "Terminal"
				do script "cd \\"\(escapedPath)\\" && '\(command ?? ":")'"
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
				do script "cd \\"\(escapedPath)\\" && '\(command ?? ":")'" in front window
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

	private static func openSystemTerminalInNewWindow(at path: String, command: String?) async throws {
		guard let command else {
			try await openAppInNewWindow(appName: "Terminal", at: path)
			return
		}

		let escapedPath = path
			.replacingOccurrences(of: "\\", with: "\\\\")
			.replacingOccurrences(of: "'", with: "\\'")

		let script = """
		tell application "Terminal"
			activate
			do script "cd '\(escapedPath)' && \(command)"
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
