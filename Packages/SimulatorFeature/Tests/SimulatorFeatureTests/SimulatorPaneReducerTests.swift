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
			$0[SimulatorClient.self].recordingDeviceIds = { .finished }
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
			$0[SimulatorClient.self].rotate = { _, clockwise in
				turns.withValue { $0.append(clockwise) }
				return SimulatorRotation(orientation: .landscapeLeft, interfaceRotation: .counterclockwise, interfaceFollowed: true)
			}
			$0[SimulatorClient.self].devices = { [rotated] }
			$0[SimulatorClient.self].selectedDeviceId = { _ in "A" }
		}

		await store.send(.rotateButtonTapped(clockwise: false))
		await store.receive(.devicesLoaded([rotated], storedSelection: "A")) {
			$0.devices = [rotated]
		}
		#expect(turns.value == [false])
	}

	/// The device turns but the app stays put: without a word the button would seem broken.
	@Test
	func aRotationTheAppDoesNotFollowIsExplained() async {
		let booted = Self.device("A", state: .booted)
		let clock = TestClock()

		var initial = SimulatorPaneReducer.State()
		initial.devices = [booted]
		initial.selectedDeviceId = "A"
		initial.hasLoadedDevices = true
		let store = TestStore(initialState: initial) {
			SimulatorPaneReducer()
		} withDependencies: {
			$0[SimulatorClient.self].rotate = { _, _ in
				SimulatorRotation(orientation: .landscapeRight, interfaceRotation: .upright, interfaceFollowed: false)
			}
			$0[SimulatorClient.self].devices = { [booted] }
			$0[SimulatorClient.self].selectedDeviceId = { _ in "A" }
			$0.continuousClock = clock
		}

		await store.send(.rotateButtonTapped(clockwise: true))
		await store.receive(.devicesLoaded([booted], storedSelection: "A"))
		let notice = SimulatorPaneReducer.Notice(
			icon: "rotate.right",
			title: "Turned to landscape right",
			subtitle: "The app or home screen doesn't support it, so the screen stays portrait."
		)
		await store.receive(.featureFinished(notice, errorMessage: nil)) {
			$0.notice = notice
		}
		await clock.advance(by: .seconds(6))
		await store.receive(.noticeDismissed) {
			$0.notice = nil
		}
	}

	@Test
	func foldTogglesADuoAndReloadsTheDevices() async {
		let closed = SimulatorDevice(
			id: "A",
			name: "iPhone Duo",
			runtimeName: "iOS 27.1",
			state: .booted,
			screenPixelSize: CGSize(width: 1398, height: 2034),
			screenScale: 3,
			fold: .closed
		)
		let open = SimulatorDevice(
			id: "A",
			name: "iPhone Duo",
			runtimeName: "iOS 27.1",
			state: .booted,
			screenPixelSize: CGSize(width: 2007, height: 2853),
			screenScale: 3,
			rotation: .clockwise,
			fold: .open,
			screenID: 3
		)
		let folds = LockIsolated<[SimulatorFold]>([])

		var initial = SimulatorPaneReducer.State()
		initial.devices = [closed]
		initial.selectedDeviceId = "A"
		initial.hasLoadedDevices = true
		let store = TestStore(initialState: initial) {
			SimulatorPaneReducer()
		} withDependencies: {
			$0[SimulatorClient.self].setFold = { _, fold in folds.withValue { $0.append(fold) } }
			$0[SimulatorClient.self].devices = { [open] }
			$0[SimulatorClient.self].selectedDeviceId = { _ in "A" }
		}

		await store.send(.foldButtonTapped) {
			$0.transitioningDeviceId = "A"
		}
		await store.receive(.devicesLoaded([open], storedSelection: "A")) {
			$0.devices = [open]
		}
		await store.receive(.transitionFinished(errorMessage: nil)) {
			$0.transitioningDeviceId = nil
		}
		#expect(folds.value == [.open])
	}

	@Test
	func theHingeMenuPartiallyOpensADuoAndSkipsTheStateItIsIn() async {
		let closed = SimulatorDevice(
			id: "A",
			name: "iPhone Duo",
			runtimeName: "iOS 27.1",
			state: .booted,
			screenPixelSize: CGSize(width: 1398, height: 2034),
			screenScale: 3,
			fold: .closed
		)
		let partlyOpen = SimulatorDevice(
			id: "A",
			name: "iPhone Duo",
			runtimeName: "iOS 27.1",
			state: .booted,
			screenPixelSize: CGSize(width: 2007, height: 2853),
			screenScale: 3,
			rotation: .clockwise,
			fold: .partiallyOpen,
			screenID: 3
		)
		let folds = LockIsolated<[SimulatorFold]>([])

		var initial = SimulatorPaneReducer.State()
		initial.devices = [closed]
		initial.selectedDeviceId = "A"
		initial.hasLoadedDevices = true
		let store = TestStore(initialState: initial) {
			SimulatorPaneReducer()
		} withDependencies: {
			$0[SimulatorClient.self].setFold = { _, fold in folds.withValue { $0.append(fold) } }
			$0[SimulatorClient.self].devices = { [partlyOpen] }
			$0[SimulatorClient.self].selectedDeviceId = { _ in "A" }
		}

		await store.send(.foldSelected(.closed))
		await store.send(.foldSelected(.partiallyOpen)) {
			$0.transitioningDeviceId = "A"
		}
		await store.receive(.devicesLoaded([partlyOpen], storedSelection: "A")) {
			$0.devices = [partlyOpen]
		}
		await store.receive(.transitionFinished(errorMessage: nil)) {
			$0.transitioningDeviceId = nil
		}
		#expect(folds.value == [.partiallyOpen])

		// The header's Fold button closes a partially open device.
		await store.send(.foldButtonTapped) {
			$0.transitioningDeviceId = "A"
		}
		await store.receive(.devicesLoaded([partlyOpen], storedSelection: "A"))
		await store.receive(.transitionFinished(errorMessage: nil)) {
			$0.transitioningDeviceId = nil
		}
		#expect(folds.value == [.partiallyOpen, .closed])
	}

	@Test
	func foldDoesNothingForADeviceThatDoesNotFold() async {
		var initial = SimulatorPaneReducer.State()
		initial.devices = [Self.device("A", state: .booted)]
		initial.selectedDeviceId = "A"
		let store = TestStore(initialState: initial) {
			SimulatorPaneReducer()
		}
		await store.send(.foldButtonTapped)
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
			$0.notice = .init(icon: "camera.fill", title: "Screenshot saved", subtitle: "Simulator Screenshot.png", fileURL: url)
		}
		await clock.advance(by: .seconds(6))
		await store.receive(.noticeDismissed) {
			$0.notice = nil
		}
	}

	@Test
	func showingTheScreenshotInFinderClosesTheBanner() async {
		let url = URL(fileURLWithPath: "/tmp/Simulator Screenshot.png")
		let revealed = LockIsolated<[URL]>([])
		var initial = SimulatorPaneReducer.State()
		initial.notice = .init(icon: "camera.fill", title: "Screenshot saved", fileURL: url)
		let store = TestStore(initialState: initial) {
			SimulatorPaneReducer()
		} withDependencies: {
			$0[SimulatorClient.self].revealInFinder = { url in revealed.withValue { $0.append(url) } }
		}

		await store.send(.showNoticeFileInFinderTapped) {
			$0.notice = nil
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

	@Test
	func theRecordButtonStartsAndThenSavesARecording() async {
		let clock = TestClock()
		let url = URL(fileURLWithPath: "/tmp/Simulator Screen Recording.mov")
		let recording = SimulatorRecording(url: url, duration: .seconds(4))
		var initial = SimulatorPaneReducer.State()
		initial.devices = [Self.device("A", state: .booted)]
		initial.selectedDeviceId = "A"
		let store = TestStore(initialState: initial) {
			SimulatorPaneReducer()
		} withDependencies: {
			$0[SimulatorClient.self].startRecording = { _ in }
			$0[SimulatorClient.self].stopRecording = { _ in recording }
			$0.continuousClock = clock
		}

		await store.send(.recordButtonTapped) {
			$0.isTogglingRecording = true
		}
		await store.receive(.recordingStarted(deviceId: "A")) {
			$0.isTogglingRecording = false
			$0.recordingDeviceIds = ["A"]
		}
		#expect(store.state.isRecordingSelectedDevice)

		await store.send(.recordButtonTapped) {
			$0.isTogglingRecording = true
		}
		await store.receive(.recordingSaved(recording, deviceId: "A")) {
			$0.isTogglingRecording = false
			$0.recordingDeviceIds = []
			$0.notice = .init(icon: "record.circle", title: "Recording saved", subtitle: "Simulator Screen Recording.mov", fileURL: url)
		}
		await clock.advance(by: .seconds(6))
		await store.receive(.noticeDismissed) {
			$0.notice = nil
		}
	}

	@Test
	func aRecordingOfADeviceThatShutDownCanStillBeStopped() async {
		let url = URL(fileURLWithPath: "/tmp/r.mov")
		let recording = SimulatorRecording(url: url, duration: .seconds(4), endedEarly: "simctl stopped recording")
		var initial = SimulatorPaneReducer.State()
		initial.devices = [Self.device("A", state: .shutdown)]
		initial.selectedDeviceId = "A"
		initial.recordingDeviceIds = ["A"]
		let store = TestStore(initialState: initial) {
			SimulatorPaneReducer()
		} withDependencies: {
			$0[SimulatorClient.self].stopRecording = { _ in recording }
			$0.continuousClock = TestClock()
		}
		store.exhaustivity = .off

		await store.send(.recordButtonTapped)
		await store.receive(.recordingSaved(recording, deviceId: "A")) {
			$0.notice?.title = "Recording had already stopped"
		}
	}

	@Test
	func aShutDownDeviceCannotStartRecording() async {
		var initial = SimulatorPaneReducer.State()
		initial.devices = [Self.device("A", state: .shutdown)]
		initial.selectedDeviceId = "A"
		let store = TestStore(initialState: initial) {
			SimulatorPaneReducer()
		}
		await store.send(.recordButtonTapped)
	}

	@Test
	func recordingsStartedElsewhereAreFollowed() async {
		let store = TestStore(initialState: SimulatorPaneReducer.State()) {
			SimulatorPaneReducer()
		}
		await store.send(.recordingDeviceIdsChanged(["A", "B"])) {
			$0.recordingDeviceIds = ["A", "B"]
		}
	}

	@Test
	func memoryWarningAndLocationReportWhatTheyDid() async {
		let clock = TestClock()
		let locations = LockIsolated<[SimulatorLocationCommand]>([])
		var initial = SimulatorPaneReducer.State()
		initial.devices = [Self.device("A", state: .booted)]
		initial.selectedDeviceId = "A"
		let store = TestStore(initialState: initial) {
			SimulatorPaneReducer()
		} withDependencies: {
			$0[SimulatorClient.self].simulateMemoryWarning = { _ in }
			$0[SimulatorClient.self].setLocation = { _, command in locations.withValue { $0.append(command) } }
			$0.continuousClock = clock
		}

		await store.send(.memoryWarningButtonTapped)
		await store.receive(.featureFinished(.init(icon: "memorychip", title: "Memory warning sent"), errorMessage: nil)) {
			$0.notice = .init(icon: "memorychip", title: "Memory warning sent")
		}
		await store.send(.locationSelected(.scenario("City Run")))
		await store.receive(.featureFinished(.init(icon: "location.fill", title: "Location: City Run"), errorMessage: nil)) {
			$0.notice = .init(icon: "location.fill", title: "Location: City Run")
		}
		let prague = SimulatorLocationCommand.places[0].coordinate
		await store.send(.locationSelected(.set(prague)))
		await store.receive(.featureFinished(.init(icon: "location.fill", title: "Location: Prague"), errorMessage: nil)) {
			$0.notice = .init(icon: "location.fill", title: "Location: Prague")
		}
		#expect(locations.value == [.scenario("City Run"), .set(prague)])
		await store.send(.noticeDismissed) {
			$0.notice = nil
		}
	}

	@Test
	func appearanceAndStatusBarReportWhatTheyDid() async {
		let settings = LockIsolated<[SimulatorUISettings]>([])
		let statusBars = LockIsolated<[SimulatorStatusBarCommand]>([])
		var initial = SimulatorPaneReducer.State()
		initial.devices = [Self.device("A", state: .booted)]
		initial.selectedDeviceId = "A"
		let store = TestStore(initialState: initial) {
			SimulatorPaneReducer()
		} withDependencies: {
			$0[SimulatorClient.self].setUISettings = { _, value in settings.withValue { $0.append(value) } }
			$0[SimulatorClient.self].setStatusBar = { _, command in statusBars.withValue { $0.append(command) } }
			$0.continuousClock = TestClock()
		}

		await store.send(.appearanceSelected(.dark))
		await store.receive(.featureFinished(.init(icon: "moon.fill", title: "Dark appearance"), errorMessage: nil)) {
			$0.notice = .init(icon: "moon.fill", title: "Dark appearance")
		}
		await store.send(.statusBarSelected(.override(.clean)))
		await store.receive(.featureFinished(.init(icon: "cellularbars", title: "Status bar overridden"), errorMessage: nil)) {
			$0.notice = .init(icon: "cellularbars", title: "Status bar overridden")
		}
		#expect(settings.value == [SimulatorUISettings(appearance: .dark)])
		#expect(statusBars.value == [.override(.clean)])
		await store.send(.noticeDismissed) {
			$0.notice = nil
		}
	}

	@Test
	func eraseAsksFirst() async {
		let erased = LockIsolated<[String]>([])
		var initial = SimulatorPaneReducer.State()
		initial.devices = [Self.device("A", state: .booted)]
		initial.selectedDeviceId = "A"
		let store = TestStore(initialState: initial) {
			SimulatorPaneReducer()
		} withDependencies: {
			$0[SimulatorClient.self].erase = { id in erased.withValue { $0.append(id) } }
			$0.continuousClock = TestClock()
		}
		let name = initial.devices[0].name

		await store.send(.eraseButtonTapped) {
			$0.alert = AlertState {
				TextState("Erase \(name)?")
			} actions: {
				ButtonState(role: .destructive, action: .confirmErase(deviceId: "A")) {
					TextState("Erase")
				}
				ButtonState(role: .cancel) {
					TextState("Cancel")
				}
			} message: {
				TextState("All apps, their data and the device's settings are deleted. A booted device is shut down and booted again.")
			}
		}
		await store.send(.alert(.dismiss)) {
			$0.alert = nil
		}
		#expect(erased.value.isEmpty)

		await store.send(.eraseButtonTapped) {
			$0.alert = AlertState {
				TextState("Erase \(name)?")
			} actions: {
				ButtonState(role: .destructive, action: .confirmErase(deviceId: "A")) {
					TextState("Erase")
				}
				ButtonState(role: .cancel) {
					TextState("Cancel")
				}
			} message: {
				TextState("All apps, their data and the device's settings are deleted. A booted device is shut down and booted again.")
			}
		}
		await store.send(.alert(.presented(.confirmErase(deviceId: "A")))) {
			$0.alert = nil
			$0.transitioningDeviceId = "A"
		}
		await store.receive(.transitionFinished(errorMessage: nil)) {
			$0.transitioningDeviceId = nil
		}
		await store.receive(.featureFinished(.init(icon: "trash", title: "Erased \(name)"), errorMessage: nil)) {
			$0.notice = .init(icon: "trash", title: "Erased \(name)")
		}
		#expect(erased.value == ["A"])
		await store.send(.noticeDismissed) {
			$0.notice = nil
		}
	}

	@Test
	func aFailedFeatureIsReported() async {
		var initial = SimulatorPaneReducer.State()
		initial.devices = [Self.device("A", state: .booted)]
		initial.selectedDeviceId = "A"
		let store = TestStore(initialState: initial) {
			SimulatorPaneReducer()
		} withDependencies: {
			$0[SimulatorClient.self].simulateMemoryWarning = { _ in throw SimulatorError.memoryWarningUnavailable }
		}

		await store.send(.memoryWarningButtonTapped)
		await store.receive(.featureFinished(nil, errorMessage: SimulatorError.memoryWarningUnavailable.localizedDescription)) {
			$0.errorMessage = SimulatorError.memoryWarningUnavailable.localizedDescription
		}
	}
}
