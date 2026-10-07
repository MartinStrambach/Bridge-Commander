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
			$0[SimulatorClient.self].selectDevice = { id, _ in stored.setValue(id) }
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
		initial.$visibleRepositoryPaths.withLock { $0 = [] }
		initial.repositoryPath = "/repos/app"
		let store = TestStore(initialState: initial) {
			SimulatorPaneReducer()
		}

		await store.send(.activityReported(deviceId: "B", repositoryPath: "/repos/app")) {
			$0.$visibleRepositoryPaths.withLock { $0 = ["/repos/app"] }
			$0.selectedDeviceId = "B"
		}
		#expect(store.state.isVisible(in: "/repos/app"))
		#expect(!store.state.isVisible(in: "/repos/app-worktree"))
	}

	@Test
	func activityFromAnotherRepositoryLeavesTheShownDevice() async {
		var initial = SimulatorPaneReducer.State()
		initial.devices = [Self.device("A", state: .booted), Self.device("B", state: .booted)]
		initial.selectedDeviceId = "A"
		initial.repositoryPath = "/repos/app"
		initial.$visibleRepositoryPaths.withLock { $0 = ["/repos/app"] }
		let store = TestStore(initialState: initial) {
			SimulatorPaneReducer()
		}

		await store.send(.activityReported(deviceId: "B", repositoryPath: "/repos/app-ipad")) {
			$0.$visibleRepositoryPaths.withLock { $0 = ["/repos/app", "/repos/app-ipad"] }
		}
	}

	@Test
	func eachRepositoryShowsItsOwnDevice() async {
		let iPhone = Self.device("A", state: .booted)
		let iPad = Self.device("B", state: .booted)
		let choices = ["/repos/app": "A", "/repos/app-ipad": "B"]
		let selections = LockIsolated<[String: String]>([:])
		let clock = TestClock()
		let store = TestStore(initialState: SimulatorPaneReducer.State()) {
			SimulatorPaneReducer()
		} withDependencies: {
			$0[SimulatorClient.self].devices = { [iPhone, iPad] }
			$0[SimulatorClient.self].selectedDeviceId = { path in path.flatMap { selections.value[$0] ?? choices[$0] } }
			$0[SimulatorClient.self].selectDevice = { id, path in selections.withValue { $0[path ?? ""] = id } }
			$0[SimulatorClient.self].isClaudeCodeConnected = { true }
			$0[SimulatorClient.self].prepareInput = { _ in }
			$0.continuousClock = clock
		}

		let appTask = await store.send(.task(repositoryPath: "/repos/app")) {
			$0.repositoryPath = "/repos/app"
		}
		await store.receive(.claudeCodeStatusChecked(true))
		await store.receive(.devicesLoaded([iPhone, iPad], storedSelection: "A")) {
			$0.devices = [iPhone, iPad]
			$0.hasLoadedDevices = true
			$0.selectedDeviceId = "A"
		}
		await appTask.cancel()

		let iPadTask = await store.send(.task(repositoryPath: "/repos/app-ipad")) {
			$0.repositoryPath = "/repos/app-ipad"
			$0.selectedDeviceId = nil
		}
		await store.receive(.claudeCodeStatusChecked(true))
		await store.receive(.devicesLoaded([iPhone, iPad], storedSelection: "B")) {
			$0.selectedDeviceId = "B"
		}

		await store.send(.deviceSelected("A")) {
			$0.selectedDeviceId = "A"
		}
		#expect(selections.value == ["/repos/app-ipad": "A"])
		await iPadTask.cancel()
	}

	@Test
	func eachRepositoryShowsThePaneOnItsOwn() async {
		let initial = SimulatorPaneReducer.State()
		initial.$visibleRepositoryPaths.withLock { $0 = [] }
		let store = TestStore(initialState: initial) {
			SimulatorPaneReducer()
		}

		await store.send(.toggleVisibility(repositoryPath: "/repos/app")) {
			$0.$visibleRepositoryPaths.withLock { $0 = ["/repos/app"] }
		}
		await store.send(.toggleVisibility(repositoryPath: "/repos/app-worktree")) {
			$0.$visibleRepositoryPaths.withLock { $0 = ["/repos/app", "/repos/app-worktree"] }
		}
		await store.send(.closeButtonTapped(repositoryPath: "/repos/app")) {
			$0.$visibleRepositoryPaths.withLock { $0 = ["/repos/app-worktree"] }
		}
		await store.send(.toggleVisibility(repositoryPath: "/repos/app-worktree")) {
			$0.$visibleRepositoryPaths.withLock { $0 = [] }
		}
		#expect(!store.state.isVisible(in: nil))
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
			$0[SimulatorClient.self].selectedDeviceId = { _ in "A" }
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
