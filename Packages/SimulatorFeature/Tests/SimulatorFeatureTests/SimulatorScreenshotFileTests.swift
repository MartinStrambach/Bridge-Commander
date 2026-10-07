import Foundation
import Testing
@testable import SimulatorFeature

struct SimulatorScreenshotFileTests {
	private let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)

	@Test
	func nameFollowsSimulatorApp() {
		let date = Date(timeIntervalSince1970: 1_791_381_802) // 2026-10-07 14:03:22 UTC
		let name = SimulatorScreenshotFile.name(deviceName: "iPhone 17 Pro", date: date, timeZone: TimeZone(identifier: "UTC")!)
		#expect(name == "Simulator Screenshot - iPhone 17 Pro - 2026-10-07 at 14.03.22.png")
	}

	@Test
	func slashesInTheDeviceNameDoNotMakeFolders() {
		let name = SimulatorScreenshotFile.name(deviceName: "iPad Pro 13/M5", date: .now)
		#expect(name.hasPrefix("Simulator Screenshot - iPad Pro 13-M5 - "))
	}

	@Test
	func simulatorAppsLocationWins() {
		let folder = SimulatorScreenshotFile.folder(
			simulatorLocation: "~/Screens",
			systemLocation: "/Volumes/Shots",
			home: home,
			isDirectory: { _ in true }
		)
		#expect(folder.path == ("~/Screens" as NSString).expandingTildeInPath)
	}

	@Test
	func aMissingFolderFallsThroughToTheNext() {
		let folder = SimulatorScreenshotFile.folder(
			simulatorLocation: "/gone",
			systemLocation: "/Volumes/Shots",
			home: home,
			isDirectory: { $0.path == "/Volumes/Shots" }
		)
		#expect(folder.path == "/Volumes/Shots")
	}

	@Test
	func withoutLocationsItIsTheDesktop() {
		let folder = SimulatorScreenshotFile.folder(simulatorLocation: nil, systemLocation: "", home: home, isDirectory: { _ in true })
		#expect(folder.path == "/Users/someone/Desktop")
	}

	@Test
	func aTakenNameGetsANumber() {
		let folder = URL(fileURLWithPath: "/Shots", isDirectory: true)
		let taken: Set<String> = ["/Shots/Shot.png", "/Shots/Shot 2.png"]
		let url = SimulatorScreenshotFile.unusedURL(in: folder, name: "Shot.png", exists: { taken.contains($0.path) })
		#expect(url.path == "/Shots/Shot 3.png")
	}
}
