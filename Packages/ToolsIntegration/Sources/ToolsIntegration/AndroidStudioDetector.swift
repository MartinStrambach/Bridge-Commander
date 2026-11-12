import AppKit
import Foundation

public nonisolated enum AndroidStudioDetector {
	public static let bundleIdentifier = "com.google.android.studio"

	/// Checks if Android Studio is running
	/// - Returns: true if Android Studio process is found
	public static func isAndroidStudioRunning() -> Bool {
		let workspace = NSWorkspace.shared
		for app in workspace.runningApplications {
			if app.bundleIdentifier == "com.google.android.studio" {
				return true
			}
		}
		return false
	}

	/// Checks if the specified project is already open in Android Studio, or in another JetBrains IDE
	/// - Parameters:
	///   - projectPath: The full path to the project directory
	///   - bundleIdentifier: The IDE to look in
	/// - Returns: true if the project is open in any of the IDE's windows
	public static func isProjectAlreadyOpen(
		at projectPath: String,
		bundleIdentifier: String = AndroidStudioDetector.bundleIdentifier
	) -> Bool {
		guard
			let androidStudioApp = NSRunningApplication
				.runningApplications(withBundleIdentifier: bundleIdentifier)
				.first
		else {
			return false
		}

		// Get the accessibility element for Android Studio
		let systemElement = AXUIElementCreateApplication(androidStudioApp.processIdentifier)
		var windowsArray: AnyObject?

		// Get all windows
		let result = AXUIElementCopyAttributeValue(systemElement, kAXWindowsAttribute as CFString, &windowsArray)
		guard result == .success, let windows = windowsArray as? [AnyObject] else {
			return false
		}

		// Check each window title for the project path
		for window in windows {
			let windowElement = window as! AXUIElement
			var title: AnyObject?
			if
				AXUIElementCopyAttributeValue(windowElement, kAXTitleAttribute as CFString, &title) == .success,
				let windowTitle = title as? String
			{
				// Android Studio window titles typically contain the project name
				// Check if the project path or project name is in the window title
				let projectName = URL(fileURLWithPath: projectPath).lastPathComponent
				if windowTitle.contains(projectName) || windowTitle.contains(projectPath) {
					return true
				}
			}
		}

		return false
	}

	/// Activates (focuses) the Android Studio (or other JetBrains IDE) window containing the specified project
	/// - Parameters:
	///   - projectPath: The full path to the project directory
	///   - bundleIdentifier: The IDE to look in
	/// - Returns: true if a window was found and activated
	public static func focusProjectWindow(
		at projectPath: String,
		bundleIdentifier: String = AndroidStudioDetector.bundleIdentifier
	) -> Bool {
		guard
			let androidStudioApp = NSRunningApplication
				.runningApplications(withBundleIdentifier: bundleIdentifier)
				.first
		else {
			return false
		}

		// Get the accessibility element for Android Studio
		let systemElement = AXUIElementCreateApplication(androidStudioApp.processIdentifier)
		var windowsArray: AnyObject?

		// Get all windows
		let result = AXUIElementCopyAttributeValue(systemElement, kAXWindowsAttribute as CFString, &windowsArray)
		guard result == .success, let windows = windowsArray as? [AnyObject] else {
			return false
		}

		let projectName = URL(fileURLWithPath: projectPath).lastPathComponent

		// Find and focus the matching window
		for window in windows {
			let windowElement = window as! AXUIElement
			var title: AnyObject?
			if
				AXUIElementCopyAttributeValue(windowElement, kAXTitleAttribute as CFString, &title) == .success,
				let windowTitle = title as? String
			{
				if windowTitle.contains(projectName) || windowTitle.contains(projectPath) {
					// Activate the window
					AXUIElementSetAttributeValue(windowElement, kAXMainAttribute as CFString, true as CFBoolean)

					// Activate the application
					androidStudioApp.activate(options: .activateAllWindows)
					return true
				}
			}
		}

		return false
	}
}
