import Foundation
import Testing
@testable import SimulatorFeature

struct SimulatorDeviceSettingsTests {
	@Test
	func eachUISettingIsItsOwnSimctlCall() throws {
		let settings = SimulatorUISettings(appearance: .dark, contentSize: "increment", increaseContrast: false)
		#expect(try settings.simctlCommands(udid: "U") == [
			["ui", "U", "appearance", "dark"],
			["ui", "U", "content_size", "increment"],
			["ui", "U", "increase_contrast", "disabled"],
		])
	}

	@Test
	func uiSettingsNeedSomethingKnown() {
		#expect(throws: SimulatorError.self) { try SimulatorUISettings().simctlCommands(udid: "U") }
		#expect(throws: SimulatorError.self) { try SimulatorUISettings(contentSize: "huge").simctlCommands(udid: "U") }
	}

	@Test
	func cleanStatusBarIsAppleMarketingOne() throws {
		#expect(try SimulatorStatusBarCommand.override(.clean).simctlArguments(udid: "U") == [
			"status_bar", "U", "override",
			"--time", "9:41", "--dataNetwork", "wifi", "--wifiMode", "active", "--wifiBars", "3",
			"--cellularMode", "active", "--cellularBars", "4", "--operatorName", "",
			"--batteryState", "charged", "--batteryLevel", "100",
		])
		#expect(try SimulatorStatusBarCommand.clear.simctlArguments(udid: "U") == ["status_bar", "U", "clear"])
	}

	@Test
	func statusBarValuesOutOfRangeAreRefused() {
		let refused: [SimulatorStatusBarOverride] = [
			SimulatorStatusBarOverride(),
			SimulatorStatusBarOverride(wifiBars: 4),
			SimulatorStatusBarOverride(cellularBars: -1),
			SimulatorStatusBarOverride(batteryLevel: 101),
			SimulatorStatusBarOverride(dataNetwork: "6g"),
			SimulatorStatusBarOverride(batteryState: "full"),
		]
		for values in refused {
			#expect(throws: SimulatorError.self, "\(values)") {
				try SimulatorStatusBarCommand.override(values).simctlArguments(udid: "U")
			}
		}
	}

	// MARK: - Launching

	@Test
	func defaultLogPredicateKeepsTheAppsSubsystemAndItsErrors() {
		#expect(SimulatorAppLauncher.defaultLogPredicate(bundleId: "com.example.App", executable: "My App")
			== #"process == "My App" AND (subsystem BEGINSWITH "com.example.App" OR messageType == error OR messageType == fault)"#)
		#expect(SimulatorAppLauncher.defaultLogPredicate(bundleId: "a", executable: #"Odd"Name"#).hasPrefix(#"process == "Odd\"Name""#))
	}

	@Test
	func logFileNamesNeedNoQuoting() throws {
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = .current
		let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 14, minute: 3, second: 5)))
		#expect(SimulatorAppLauncher.logFileName(bundleId: "com.example.App", date: date) == "com.example.App_2026-10-10_14-03-05.log")
		#expect(SimulatorAppLauncher.logFileName(bundleId: "odd id/x", date: date, number: 2) == "odd_id_x_2026-10-10_14-03-05_2.log")
	}

	@Test
	func environmentGetsSimctlsChildPrefix() {
		#expect(SimulatorAppLauncher.childEnvironment(["MODE": "demo", "SIMCTL_CHILD_DEBUG": "1"])
			== ["SIMCTL_CHILD_MODE": "demo", "SIMCTL_CHILD_DEBUG": "1"])
	}

	@Test
	func processIdComesFromSimctlLaunchOutput() {
		#expect(SimulatorAppLauncher.processId(fromLaunchOutput: "com.example.App: 38237\n") == 38237)
		#expect(SimulatorAppLauncher.processId(fromLaunchOutput: "An error was encountered") == nil)
	}

	@Test
	func executableFallsBackToTheBundlesName() {
		#expect(SimulatorAppLauncher.executableName(appPath: "/nonexistent/Demo.app") == "Demo")
	}
}
