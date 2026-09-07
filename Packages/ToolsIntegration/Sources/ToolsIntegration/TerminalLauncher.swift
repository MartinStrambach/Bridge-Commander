import AppKit
import CoreGraphics
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

	/// Opens `path` in Terminal.app, adding a tab to the session that is already open when
	/// `newTab` is set.
	///
	/// Adding a tab is the one case that cannot be done in AppleScript alone, so it runs in three
	/// steps: ask Terminal for the front tab, post ⌘T from this process, then run the command in
	/// whatever session that produced.
	private static func openSystemTerminal(at path: String, command: String?, newTab: Bool) async throws {
		let commandLiteral = appleScriptLiteral(shellCommand(at: path, command: command))

		let sessionTTY = try await prepareSystemTerminal(commandLiteral: commandLiteral, newTab: newTab)

		// Non-empty only when a tab still has to be made; every other case is already finished.
		guard !sessionTTY.isEmpty else {
			return
		}

		try await runInNewSystemTerminalTab(
			commandLiteral: commandLiteral,
			replacing: requestNewTerminalTab() ? sessionTTY : nil
		)
	}

	/// Brings Terminal up and handles every case that AppleScript can finish on its own, returning
	/// `""` once the command has been run. A non-empty result is the `tty` of the front window's
	/// selected tab, meaning a tab still has to be made.
	///
	/// Terminal opens a window at the user's home directory as soon as it launches, and a plain
	/// `do script` (no target) always makes *another* window — so launching it cold used to leave
	/// two windows behind, the startup one at home plus the requested one. Reuse that startup
	/// window instead, and only ask for a fresh tab or window when there was a session to add to.
	private static func prepareSystemTerminal(commandLiteral: String, newTab: Bool) async throws -> String {
		try await runAppleScript(prepareScript(commandLiteral: commandLiteral, newTab: newTab))
			.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	internal static func prepareScript(commandLiteral: String, newTab: Bool) -> String {
		// Terminal's own ⌘T needs a key window to attach a tab to, so wait for it to actually come
		// forward before the caller posts the keystroke.
		let newTabBranch = """
			repeat 20 times
				if frontmost then exit repeat
				delay 0.05
			end repeat
			set frontTTY to ""
			try
				set frontTTY to (tty of selected tab of front window) as text
			end try
			if frontTTY is "" then
				do script \(commandLiteral)
				return ""
			end if
			return frontTTY
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
				return ""
			end if
			if not wasRunning then
				do script \(commandLiteral) in front window
				return ""
			end if
		\(newTab ? newTabBranch : "\tdo script \(commandLiteral)\n\treturn \"\"")
		end tell
		"""

		return script
	}

	/// Runs the command in the session ⌘T just created, identified as the front window's selected
	/// tab no longer being `previousTTY`. Terminal reports the new tab asynchronously, so poll for
	/// it rather than guessing a delay — otherwise the command lands in the tab that was already
	/// there. Depending on Terminal's settings ⌘T may produce a window instead of a tab; either
	/// way the front window's selected tab is the fresh one.
	///
	/// `previousTTY` is `nil` when the keystroke could not be posted at all. Then, and if the tab
	/// never shows up, fall back to a plain `do script`: the user gets a window instead of a tab,
	/// which beats both opening nothing and typing into a tab that may have something running in
	/// it. `RepositoryListView`'s Accessibility banner explains why.
	private static func runInNewSystemTerminalTab(commandLiteral: String, replacing previousTTY: String?) async throws {
		try await runAppleScript(newTabScript(commandLiteral: commandLiteral, replacing: previousTTY))
	}

	internal static func newTabScript(commandLiteral: String, replacing previousTTY: String?) -> String {
		guard let previousTTY else {
			return "tell application \"Terminal\" to do script \(commandLiteral)"
		}

		let script = """
		tell application "Terminal"
			set hasFreshTab to false
			try
				repeat 40 times
					if (count of windows) > 0 then
						if (tty of selected tab of front window) as text is not \(appleScriptLiteral(previousTTY)) then
							set hasFreshTab to true
							exit repeat
						end if
					end if
					delay 0.05
				end repeat
			end try
			if hasFreshTab then
				do script \(commandLiteral) in front window
			else
				do script \(commandLiteral)
			end if
		end tell
		"""

		return script
	}

	/// Asks Terminal for a new tab by posting ⌘T, returning whether the keystroke went out.
	///
	/// This has to be posted from *this* process. Terminal's scripting dictionary cannot make a tab
	/// (`make new tab` fails with -10000), so a keystroke is the only route, and macOS checks the
	/// Accessibility grant of whoever posts the event. Handing the job to an `osascript` child gets
	/// it checked against `osascript`, which has no grant of its own — it fails with "osascript is
	/// not allowed to send keystrokes" no matter what the user granted this app.
	private static func requestNewTerminalTab() -> Bool {
		guard PermissionChecker.isAccessibilityPermitted() else {
			return false
		}

		let tKeyCode: CGKeyCode = 0x11 // kVK_ANSI_T

		guard
			let source = CGEventSource(stateID: .combinedSessionState),
			let keyDown = CGEvent(keyboardEventSource: source, virtualKey: tKeyCode, keyDown: true),
			let keyUp = CGEvent(keyboardEventSource: source, virtualKey: tKeyCode, keyDown: false)
		else {
			return false
		}

		keyDown.flags = .maskCommand
		keyUp.flags = .maskCommand
		keyDown.post(tap: .cghidEventTap)
		keyUp.post(tap: .cghidEventTap)

		return true
	}

	@discardableResult
	private static func runAppleScript(_ script: String) async throws -> String {
		let result = await ProcessRunner.run(
			executableURL: URL(filePath: "/usr/bin/osascript"),
			arguments: ["-e", script]
		)

		if !result.success {
			throw TerminalLauncherError.failed(result.errorString)
		}

		return result.outputString
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
