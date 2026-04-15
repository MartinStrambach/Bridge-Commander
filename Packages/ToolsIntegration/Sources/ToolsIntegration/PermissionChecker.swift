import ApplicationServices
import Foundation
import ProcessExecution

public nonisolated enum PermissionChecker {
	/// Returns `true` if the app has been granted Accessibility permission.
	public static func isAccessibilityPermitted() -> Bool {
		AXIsProcessTrusted()
	}

	/// Checks whether Automation permission for System Events is granted by running
	/// a harmless osascript probe. Returns `true` if permitted, `false` if denied.
	public static func isSystemEventsAutomationPermitted() async -> Bool {
		let script = """
		tell application "System Events"
		    get name of processes
		end tell
		"""

		let result = await ProcessRunner.run(
			executableURL: URL(filePath: "/usr/bin/osascript"),
			arguments: ["-e", script]
		)
		return result.success
	}
}
