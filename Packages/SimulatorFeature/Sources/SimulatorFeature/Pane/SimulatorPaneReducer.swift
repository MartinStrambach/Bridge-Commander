import ComposableArchitecture
import Foundation

@Reducer
public struct SimulatorPaneReducer {
	@ObservableState
	public struct State: Equatable {
		/// Remembered across launches and across the terminal panel being hidden, like the rest of
		/// the panel's layout.
		@Shared(.appStorage("simulatorPaneVisible"))
		public var isVisible = false

		public var devices: [SimulatorDevice] = []
		public var selectedDeviceId: String?
		public var hasLoadedDevices = false
		/// The device a boot or shutdown is running for.
		public var transitioningDeviceId: String?
		/// What the last boot, shutdown, button press or Claude Code registration reported.
		public var errorMessage: String?
		/// Why the device list could not be read (CoreSimulator missing, say); cleared by the next
		/// successful poll.
		public var loadErrorMessage: String?
		/// Assumed until checked, so the "connect" banner does not flash on every appearance.
		public var isClaudeCodeConnected = true
		public var isConnectingClaudeCode = false
		public var isSavingScreenshot = false
		/// The screenshot just saved, offered in a banner until it times out or is dismissed.
		public var savedScreenshotURL: URL?

		public init() {}

		public var selectedDevice: SimulatorDevice? {
			selectedDeviceId.flatMap { id in devices.first { $0.id == id } }
		}
	}

	public enum Action: Equatable {
		case onAppear
		case onDisappear
		case devicesLoaded([SimulatorDevice], storedSelection: String?)
		case devicesFailed(String)
		case deviceSelected(String)
		case bootButtonTapped
		case shutdownButtonTapped
		case transitionFinished(errorMessage: String?)
		case hardwareButtonTapped(SimulatorHardwareButton)
		case rotateButtonTapped(clockwise: Bool)
		case screenshotButtonTapped
		case screenshotSaved(URL)
		case screenshotFailed(String)
		case showScreenshotInFinderTapped
		case screenshotBannerDismissed
		case connectClaudeCodeButtonTapped
		case claudeCodeStatusChecked(Bool)
		case connectClaudeCodeFinished(errorMessage: String?)
		case errorDismissed
		case toggleVisibility
		case closeButtonTapped
		/// An MCP tool call touched `deviceId`: show it.
		case activityReported(deviceId: String)
	}

	private enum CancelId {
		case polling
		case screenshotBanner
	}

	@Dependency(SimulatorClient.self)
	private var simulatorClient

	@Dependency(\.continuousClock)
	private var clock

	public init() {}

	public var body: some Reducer<State, Action> {
		Reduce { state, action in
			switch action {
			case .onAppear:
				// Device state changes outside the pane too — `simctl boot` in a terminal, Claude
				// booting one — so the list is polled while the pane is on screen. CoreSimulator
				// answers from its in-process cache; this is cheap.
				return .merge(
					.run { [simulatorClient] send in
						await send(.claudeCodeStatusChecked(simulatorClient.isClaudeCodeConnected()))
					},
					.run { [simulatorClient, clock] send in
						while !Task.isCancelled {
							do {
								let devices = try await simulatorClient.devices()
								await send(.devicesLoaded(devices, storedSelection: simulatorClient.selectedDeviceId()))
							}
							catch {
								await send(.devicesFailed(error.localizedDescription))
							}
							try await clock.sleep(for: .seconds(1.5))
						}
					}
					.cancellable(id: CancelId.polling, cancelInFlight: true)
				)

			case .onDisappear:
				return .cancel(id: CancelId.polling)

			case let .devicesLoaded(devices, storedSelection):
				let previouslyBooted = state.selectedDevice?.isBooted ?? false
				state.devices = devices
				state.hasLoadedDevices = true
				state.loadErrorMessage = nil

				// The stored selection is the shared one: the MCP tools move it to the device they
				// act on, and the pane follows.
				let selection = storedSelection.flatMap { id in devices.first { $0.id == id } }
					?? devices.first(where: \.isBooted)
					?? devices.first
				state.selectedDeviceId = selection?.id

				var effects: [Effect<Action>] = []
				if let selection, selection.id != storedSelection {
					effects.append(.run { [simulatorClient] _ in simulatorClient.selectDevice(selection.id) })
				}
				if let selection, selection.isBooted, !previouslyBooted {
					effects.append(.run { [simulatorClient] _ in await simulatorClient.prepareInput(selection.id) })
				}
				return .merge(effects)

			case let .devicesFailed(message):
				state.hasLoadedDevices = true
				state.loadErrorMessage = message
				return .none

			case let .deviceSelected(id):
				state.selectedDeviceId = id
				state.errorMessage = nil
				return .run { [simulatorClient] _ in
					simulatorClient.selectDevice(id)
				}

			case .bootButtonTapped:
				guard let device = state.selectedDevice, state.transitioningDeviceId == nil else {
					return .none
				}
				state.transitioningDeviceId = device.id
				state.errorMessage = nil
				return .run { [simulatorClient] send in
					do {
						try await simulatorClient.boot(device.id)
						await send(.transitionFinished(errorMessage: nil))
					}
					catch {
						await send(.transitionFinished(errorMessage: error.localizedDescription))
					}
				}

			case .shutdownButtonTapped:
				guard let device = state.selectedDevice, state.transitioningDeviceId == nil else {
					return .none
				}
				state.transitioningDeviceId = device.id
				state.errorMessage = nil
				return .run { [simulatorClient] send in
					do {
						try await simulatorClient.shutdown(device.id)
						await send(.transitionFinished(errorMessage: nil))
					}
					catch {
						await send(.transitionFinished(errorMessage: error.localizedDescription))
					}
				}

			case let .transitionFinished(errorMessage):
				state.transitioningDeviceId = nil
				state.errorMessage = errorMessage
				return .none

			case let .hardwareButtonTapped(button):
				guard let device = state.selectedDevice, device.isBooted else {
					return .none
				}
				return .run { [simulatorClient] send in
					do {
						try await simulatorClient.pressButton(device.id, button)
					}
					catch {
						await send(.transitionFinished(errorMessage: error.localizedDescription))
					}
				}

			case let .rotateButtonTapped(clockwise):
				guard let device = state.selectedDevice, device.isBooted else {
					return .none
				}
				// Reloads the devices when done, so the pane takes the rotated width without
				// waiting for the next poll.
				return .run { [simulatorClient] send in
					do {
						try await simulatorClient.rotate(device.id, clockwise)
						let devices = try await simulatorClient.devices()
						await send(.devicesLoaded(devices, storedSelection: simulatorClient.selectedDeviceId()))
					}
					catch {
						await send(.transitionFinished(errorMessage: error.localizedDescription))
					}
				}

			case .screenshotButtonTapped:
				guard let device = state.selectedDevice, device.isBooted, !state.isSavingScreenshot else {
					return .none
				}
				state.isSavingScreenshot = true
				state.errorMessage = nil
				return .run { [simulatorClient] send in
					do {
						try await send(.screenshotSaved(simulatorClient.saveScreenshot(device)))
					}
					catch {
						await send(.screenshotFailed(error.localizedDescription))
					}
				}

			case let .screenshotSaved(url):
				state.isSavingScreenshot = false
				state.savedScreenshotURL = url
				return .run { [clock] send in
					try await clock.sleep(for: .seconds(6))
					await send(.screenshotBannerDismissed)
				}
				.cancellable(id: CancelId.screenshotBanner, cancelInFlight: true)

			case let .screenshotFailed(message):
				state.isSavingScreenshot = false
				state.errorMessage = "Could not save the screenshot: \(message)"
				return .none

			case .showScreenshotInFinderTapped:
				guard let url = state.savedScreenshotURL else {
					return .none
				}
				state.savedScreenshotURL = nil
				return .merge(
					.cancel(id: CancelId.screenshotBanner),
					.run { [simulatorClient] _ in await simulatorClient.revealInFinder(url) }
				)

			case .screenshotBannerDismissed:
				state.savedScreenshotURL = nil
				return .cancel(id: CancelId.screenshotBanner)

			case .connectClaudeCodeButtonTapped:
				state.isConnectingClaudeCode = true
				state.errorMessage = nil
				return .run { [simulatorClient] send in
					do {
						try await simulatorClient.connectClaudeCode()
						await send(.connectClaudeCodeFinished(errorMessage: nil))
					}
					catch {
						await send(.connectClaudeCodeFinished(errorMessage: error.localizedDescription))
					}
				}

			case let .claudeCodeStatusChecked(isConnected):
				state.isClaudeCodeConnected = isConnected
				return .none

			case let .connectClaudeCodeFinished(errorMessage):
				state.isConnectingClaudeCode = false
				state.errorMessage = errorMessage
				return .run { [simulatorClient] send in
					await send(.claudeCodeStatusChecked(simulatorClient.isClaudeCodeConnected()))
				}

			case .errorDismissed:
				state.errorMessage = nil
				return .none

			case .toggleVisibility:
				state.$isVisible.withLock { $0.toggle() }
				return .none

			case .closeButtonTapped:
				state.$isVisible.withLock { $0 = false }
				return .none

			case let .activityReported(deviceId):
				state.$isVisible.withLock { $0 = true }
				if state.devices.contains(where: { $0.id == deviceId }) {
					state.selectedDeviceId = deviceId
				}
				return .none
			}
		}
	}
}
