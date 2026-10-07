import ComposableArchitecture
import CoreGraphics
import Foundation
import Testing
@testable import SimulatorFeature

@MainActor
struct SimulatorPaneReducerTests {
	private static func device(_ id: String, state: SimulatorDevice.State) -> SimulatorDevice {
		SimulatorDevice(
			id: id,
			name: "Device \(id)",
			runtimeName: "iOS 27.0",
			state: state,
			screenPixelSize: CGSize(width: 1206, height: 2622),
			screenScale: 3
		)
	}

	@Test
	func withoutAStoredSelectionTheBootedDeviceIsChosenAndStored() async {
		let stored = LockIsolated<String?>(nil)
		let store = TestStore(initialState: SimulatorPaneReducer.State()) {
			SimulatorPaneReducer()
		} withDependencies: {
			$0[SimulatorClient.self].selectDevice = { stored.setValue($0) }
			$0[SimulatorClient.self].prepareInput = { _ in }
		}

		let shutdown = Self.device("A", state: .shutdown)
		let booted = Self.device("B", state: .booted)
		await store.send(.devicesLoaded([shutdown, booted], storedSelection: nil)) {
			$0.devices = [shutdown, booted]
			$0.hasLoadedDevices = true
			$0.selectedDeviceId = "B"
		}
		#expect(stored.value == "B")
	}

	@Test
	func theStoredSelectionWinsEvenWhenShutDown() async {
		let store = TestStore(initialState: SimulatorPaneReducer.State()) {
			SimulatorPaneReducer()
		}

		let shutdown = Self.device("A", state: .shutdown)
		let booted = Self.device("B", state: .booted)
		await store.send(.devicesLoaded([shutdown, booted], storedSelection: "A")) {
			$0.devices = [shutdown, booted]
			$0.hasLoadedDevices = true
			$0.selectedDeviceId = "A"
		}
	}

	@Test
	func activityShowsThePaneOnTheDevice() async {
		let booted = Self.device("B", state: .booted)
		var initial = SimulatorPaneReducer.State()
		initial.devices = [Self.device("A", state: .shutdown), booted]
		initial.selectedDeviceId = "A"
		initial.$isVisible.withLock { $0 = false }
		let store = TestStore(initialState: initial) {
			SimulatorPaneReducer()
		}

		await store.send(.activityReported(deviceId: "B")) {
			$0.$isVisible.withLock { $0 = true }
			$0.selectedDeviceId = "B"
		}
	}

	@Test
	func aFailedBootIsReported() async {
		struct BootFailure: LocalizedError {
			var errorDescription: String? { "Unable to boot" }
		}

		var initial = SimulatorPaneReducer.State()
		initial.devices = [Self.device("A", state: .shutdown)]
		initial.selectedDeviceId = "A"
		let store = TestStore(initialState: initial) {
			SimulatorPaneReducer()
		} withDependencies: {
			$0[SimulatorClient.self].boot = { _ in throw BootFailure() }
		}

		await store.send(.bootButtonTapped) {
			$0.transitioningDeviceId = "A"
		}
		await store.receive(.transitionFinished(errorMessage: "Unable to boot")) {
			$0.transitioningDeviceId = nil
			$0.errorMessage = "Unable to boot"
		}
	}

	@Test
	func rotatingReloadsTheDevicesSoThePaneTakesTheNewShape() async {
		let booted = Self.device("A", state: .booted)
		let rotated = SimulatorDevice(
			id: "A",
			name: booted.name,
			runtimeName: booted.runtimeName,
			state: .booted,
			screenPixelSize: booted.screenPixelSize,
			screenScale: booted.screenScale,
			rotation: .counterclockwise
		)
		let turns = LockIsolated<[Bool]>([])

		var initial = SimulatorPaneReducer.State()
		initial.devices = [booted]
		initial.selectedDeviceId = "A"
		initial.hasLoadedDevices = true
		let store = TestStore(initialState: initial) {
			SimulatorPaneReducer()
		} withDependencies: {
			$0[SimulatorClient.self].rotate = { _, clockwise in turns.withValue { $0.append(clockwise) } }
			$0[SimulatorClient.self].devices = { [rotated] }
			$0[SimulatorClient.self].selectedDeviceId = { "A" }
		}

		await store.send(.rotateButtonTapped(clockwise: false))
		await store.receive(.devicesLoaded([rotated], storedSelection: "A")) {
			$0.devices = [rotated]
		}
		#expect(turns.value == [false])
	}

	@Test
	func aSavedScreenshotIsOfferedUntilTheBannerTimesOut() async {
		let clock = TestClock()
		let url = URL(fileURLWithPath: "/tmp/Simulator Screenshot.png")
		var initial = SimulatorPaneReducer.State()
		initial.devices = [Self.device("A", state: .booted)]
		initial.selectedDeviceId = "A"
		let store = TestStore(initialState: initial) {
			SimulatorPaneReducer()
		} withDependencies: {
			$0[SimulatorClient.self].saveScreenshot = { _ in url }
			$0.continuousClock = clock
		}

		await store.send(.screenshotButtonTapped) {
			$0.isSavingScreenshot = true
		}
		await store.receive(.screenshotSaved(url)) {
			$0.isSavingScreenshot = false
			$0.savedScreenshotURL = url
		}
		await clock.advance(by: .seconds(6))
		await store.receive(.screenshotBannerDismissed) {
			$0.savedScreenshotURL = nil
		}
	}

	@Test
	func showingTheScreenshotInFinderClosesTheBanner() async {
		let url = URL(fileURLWithPath: "/tmp/Simulator Screenshot.png")
		let revealed = LockIsolated<[URL]>([])
		var initial = SimulatorPaneReducer.State()
		initial.savedScreenshotURL = url
		let store = TestStore(initialState: initial) {
			SimulatorPaneReducer()
		} withDependencies: {
			$0[SimulatorClient.self].revealInFinder = { url in revealed.withValue { $0.append(url) } }
		}

		await store.send(.showScreenshotInFinderTapped) {
			$0.savedScreenshotURL = nil
		}
		#expect(revealed.value == [url])
	}

	@Test
	func aFailedScreenshotIsReported() async {
		var initial = SimulatorPaneReducer.State()
		initial.devices = [Self.device("A", state: .booted)]
		initial.selectedDeviceId = "A"
		let store = TestStore(initialState: initial) {
			SimulatorPaneReducer()
		} withDependencies: {
			$0[SimulatorClient.self].saveScreenshot = { _ in throw SimulatorError.noFramebuffer }
		}

		await store.send(.screenshotButtonTapped) {
			$0.isSavingScreenshot = true
		}
		await store.receive(.screenshotFailed(SimulatorError.noFramebuffer.localizedDescription)) {
			$0.isSavingScreenshot = false
			$0.errorMessage = "Could not save the screenshot: \(SimulatorError.noFramebuffer.localizedDescription)"
		}
	}
}
