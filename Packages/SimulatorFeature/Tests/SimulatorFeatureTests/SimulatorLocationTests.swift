import Foundation
import Testing
@testable import SimulatorFeature

struct SimulatorLocationTests {
	private let prague = SimulatorCoordinate(latitude: 50.0755, longitude: 14.4378)
	private let brno = SimulatorCoordinate(latitude: 49.1951, longitude: 16.6068)

	@Test
	func eachCommandIsASimctlLocationAction() throws {
		#expect(try SimulatorLocationCommand.set(prague).simctlArguments(udid: "U") == ["location", "U", "set", "50.075500,14.437800"])
		#expect(try SimulatorLocationCommand.route([prague, brno], speed: nil).simctlArguments(udid: "U")
			== ["location", "U", "start", "50.075500,14.437800", "49.195100,16.606800"])
		#expect(try SimulatorLocationCommand.route([prague, brno], speed: 13.9).simctlArguments(udid: "U")
			== ["location", "U", "start", "--speed=13.90", "50.075500,14.437800", "49.195100,16.606800"])
		#expect(try SimulatorLocationCommand.scenario("City Run").simctlArguments(udid: "U") == ["location", "U", "run", "City Run"])
		#expect(try SimulatorLocationCommand.clear.simctlArguments(udid: "U") == ["location", "U", "clear"])
	}

	@Test
	func negativeCoordinatesKeepTheirSign() throws {
		let cupertino = SimulatorCoordinate(latitude: 37.3349, longitude: -122.00902)
		#expect(try SimulatorLocationCommand.set(cupertino).simctlArguments(udid: "U").last == "37.334900,-122.009020")
	}

	@Test
	func impossibleLocationsAreRefused() {
		let refused: [SimulatorLocationCommand] = [
			.set(SimulatorCoordinate(latitude: 91, longitude: 0)),
			.set(SimulatorCoordinate(latitude: 0, longitude: -181)),
			.route([prague], speed: nil),
			.route([prague, SimulatorCoordinate(latitude: 0, longitude: 200)], speed: nil),
			.route([prague, brno], speed: 0),
			.scenario("  "),
		]
		for command in refused {
			#expect(throws: SimulatorError.self, "\(command)") {
				try command.simctlArguments(udid: "U")
			}
		}
	}
}

struct SimulatorRecordingDestinationTests {
	private let date = Date(timeIntervalSince1970: 1_791_381_802) // 2026-10-07 14:03:22 UTC
	private let desktop = URL(fileURLWithPath: "/Users/someone/Desktop", isDirectory: true)
	private let folders: Set<String> = ["/Users/someone/Desktop", "/tmp", "/tmp/videos"]

	private func destination(_ requested: String?, existing: Set<String> = []) throws -> URL {
		try SimulatorScreenRecorder.destination(
			requested: requested,
			deviceName: "iPhone 17 Pro",
			date: date,
			defaultFolder: desktop,
			isDirectory: { folders.contains($0.path(percentEncoded: false).trimmingSuffix("/")) },
			exists: { existing.contains($0.path(percentEncoded: false)) }
		)
	}

	@Test
	func nameFollowsSimulatorApp() {
		let name = SimulatorScreenshotFile.recordingName(deviceName: "iPhone 17 Pro", date: date, timeZone: TimeZone(identifier: "UTC")!)
		#expect(name == "Simulator Screen Recording - iPhone 17 Pro - 2026-10-07 at 14.03.22.mov")
	}

	@Test
	func withoutAPathItGoesToTheDefaultFolder() throws {
		let url = try destination(nil)
		#expect(url.deletingLastPathComponent().path(percentEncoded: false).trimmingSuffix("/") == "/Users/someone/Desktop")
		#expect(url.lastPathComponent.hasPrefix("Simulator Screen Recording - iPhone 17 Pro - "))
		#expect(try destination("  ").deletingLastPathComponent() == url.deletingLastPathComponent())
	}

	@Test
	func aFolderGetsANamedFileInIt() throws {
		let url = try destination("/tmp/videos")
		#expect(url.deletingLastPathComponent().path(percentEncoded: false).trimmingSuffix("/") == "/tmp/videos")
		#expect(url.pathExtension == "mov")
	}

	@Test
	func aFileIsUsedAsGivenWithMovAdded() throws {
		#expect(try destination("/tmp/flow.mov").path(percentEncoded: false) == "/tmp/flow.mov")
		#expect(try destination("/tmp/flow").path(percentEncoded: false) == "/tmp/flow.mov")
	}

	@Test
	func badPathsAreRefused() {
		for path in ["flow.mov", "/tmp/flow.mp4", "/nowhere/flow.mov"] {
			#expect(throws: SimulatorError.self, "\(path)") {
				try destination(path)
			}
		}
		#expect(throws: SimulatorError.self) {
			try destination("/tmp/flow.mov", existing: ["/tmp/flow.mov"])
		}
	}
}

private extension String {
	func trimmingSuffix(_ suffix: String) -> String {
		hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
	}
}
