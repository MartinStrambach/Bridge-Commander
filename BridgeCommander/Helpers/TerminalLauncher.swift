import AppKit
import Foundation

nonisolated enum TerminalLauncher {

	static func openTerminal(at path: String, behavior: TerminalOpeningBehavior) async {
		if behavior == .newTab {
			await openTerminalInNewTab(at: path)
		}
		else {
			await openTerminalInNewWindow(at: path)
		}
	}

	private static func openTerminalInNewTab(at path: String) async {
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

	private static func openTerminalInNewWindow(at path: String) async {
		let result = await ProcessRunner.run(
			executableURL: URL(filePath: "/usr/bin/open"),
			arguments: ["-a", "Terminal", path]
		)

		if !result.success {
			print("Failed to open Terminal: \(result.errorString)")
		}
	}

}
