import Foundation
import Testing
@testable import ToolsIntegration

@Suite("Terminal launcher AppleScript")
struct TerminalLauncherScriptTests {
	private let command = "\"cd '/tmp'\""

	// MARK: - Cold Launch

	@Test("a cold launch reuses the window Terminal opens at startup", arguments: [true, false])
	func coldLaunchReusesStartupWindow(newTab: Bool) {
		let script = TerminalLauncher.prepareScript(commandLiteral: command, newTab: newTab)

		// A bare `do script` here is the bug that left a stray window at the home directory: it
		// makes a window of its own on top of the one Terminal already opened on launch.
		#expect(script.contains("if not wasRunning then\n\t\tdo script \(command) in front window"))
	}

	@Test("a cold launch waits for the startup window to appear", arguments: [true, false])
	func coldLaunchWaitsForStartupWindow(newTab: Bool) {
		let script = TerminalLauncher.prepareScript(commandLiteral: command, newTab: newTab)

		#expect(script.contains("repeat 50 times\n\t\t\tif (count of windows) > 0 then exit repeat"))
	}

	@Test("a launch that produced no window at all still opens one", arguments: [true, false])
	func launchWithoutAnyWindow(newTab: Bool) {
		let script = TerminalLauncher.prepareScript(commandLiteral: command, newTab: newTab)

		#expect(script.contains("if (count of windows) = 0 then\n\t\tdo script \(command)\n\t\treturn \"\""))
	}

	// MARK: - New Window Behavior

	@Test("the new-window behavior opens its own window and needs no keystroke")
	func newWindowWhenAlreadyRunning() {
		let script = TerminalLauncher.prepareScript(commandLiteral: command, newTab: false)

		#expect(script.hasSuffix("\tdo script \(command)\n\treturn \"\"\nend tell"))
		#expect(!script.contains("frontTTY"))
	}

	// MARK: - New Tab Behavior

	@Test("the new-tab behavior hands the front tab back instead of running the command")
	func newTabReturnsFrontTTY() {
		let script = TerminalLauncher.prepareScript(commandLiteral: command, newTab: true)

		#expect(script.hasSuffix("\treturn frontTTY\nend tell"))
	}

	@Test("the new-tab behavior waits for Terminal to come forward, so Cmd-T has a key window")
	func newTabWaitsForFrontmost() {
		let script = TerminalLauncher.prepareScript(commandLiteral: command, newTab: true)

		#expect(script.contains("if frontmost then exit repeat"))
	}

	@Test("a front tab Terminal will not report degrades to a window rather than to nothing")
	func newTabWithoutAReadableFrontTab() {
		let script = TerminalLauncher.prepareScript(commandLiteral: command, newTab: true)

		#expect(script.contains("if frontTTY is \"\" then\n\t\tdo script \(command)\n\t\treturn \"\""))
	}

	// MARK: - Running The Command In The New Tab

	@Test("a keystroke that could not be posted opens one plain window")
	func unpostableKeystrokeOpensOneWindow() {
		let script = TerminalLauncher.newTabScript(commandLiteral: command, replacing: nil)

		#expect(script == "tell application \"Terminal\" to do script \(command)")
	}

	@Test("the poll waits for a tab other than the one that was already there")
	func pollWaitsForAFreshTab() {
		let script = TerminalLauncher.newTabScript(commandLiteral: command, replacing: "/dev/ttys003")

		#expect(script.contains("is not \"/dev/ttys003\""))
		#expect(script.contains("do script \(command) in front window"))
	}

	@Test("a tab that never arrives falls back to a window instead of the tab that was there")
	func pollFallsBackToAWindow() {
		let script = TerminalLauncher.newTabScript(commandLiteral: command, replacing: "/dev/ttys003")

		#expect(script.contains("if hasFreshTab then\n\t\tdo script \(command) in front window"))
		#expect(script.contains("else\n\t\tdo script \(command)\n\tend if"))
	}

	@Test("the tty is quoted, so it cannot break out of the comparison")
	func ttyIsQuoted() {
		let script = TerminalLauncher.newTabScript(commandLiteral: command, replacing: "/dev/tty\"s")

		#expect(script.contains("is not \"/dev/tty\\\"s\""))
	}
}
