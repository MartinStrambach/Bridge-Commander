import Foundation

nonisolated enum PermissionChecker {
	/// Checks whether Automation permission for System Events is granted by running
	/// a harmless osascript probe. Returns `true` if permitted, `false` if denied.
	static func isSystemEventsAutomationPermitted() async -> Bool {
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
