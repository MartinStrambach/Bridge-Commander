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
}
