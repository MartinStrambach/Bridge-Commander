import ComposableArchitecture
import Foundation

@Reducer
public struct SimulatorPaneReducer {
	@ObservableState
	public struct State: Equatable {
		/// The repositories (worktrees included) whose terminal shows the pane: each one's is
		/// opened and closed on its own, so a worktree running the app keeps the simulator beside
		/// its terminal while another's has the full width. Remembered across launches and across
		/// the terminal panel being hidden, like the rest of the panel's layout.
		@Shared(.appStorage("simulatorPaneRepositoryPaths"))
		public var visibleRepositoryPaths: [String] = []

		/// The repository whose terminal the pane is showing beside. Each has its own device
		/// (`SimulatorClient.selectedDeviceId`), so this is what the selection is read and
		/// written for.
		public var repositoryPath: String?
		public var devices: [SimulatorDevice] = []
		public var selectedDeviceId: String?
		public var hasLoadedDevices = false
		/// The device a boot, shutdown or fold is running for.
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
		/// The devices whose screen is being recorded — from the pane or by Claude.
		public var recordingDeviceIds: Set<String> = []
		/// A recording is being started or saved.
		public var isTogglingRecording = false
		/// What just happened — a file saved, a memory warning sent — shown in a banner until it
		/// times out or is dismissed.
		public var notice: Notice?

		/// The workspace or project the Run button builds — the repository's, as its Xcode button
		/// finds it; `nil` when it has none (a Tuist project not generated yet).
		public var projectPath: String?
		/// `projectPath`'s schemes that launch an app.
		public var schemes: [XcodeScheme] = []
		public var selectedSchemeName: String?
		public var hasLoadedSchemes = false

		public init() {}

		public var selectedScheme: XcodeScheme? {
			selectedSchemeName.flatMap { name in schemes.first { $0.name == name } }
		}

		public var canRun: Bool {
			projectPath != nil && selectedScheme != nil && selectedDevice != nil
		}

		public var selectedDevice: SimulatorDevice? {
			selectedDeviceId.flatMap { id in devices.first { $0.id == id } }
		}

		public var isRecordingSelectedDevice: Bool {
			selectedDeviceId.map(recordingDeviceIds.contains) ?? false
		}

		/// Whether the pane is open beside `repositoryPath`'s terminal.
		public func isVisible(in repositoryPath: String?) -> Bool {
			repositoryPath.map(visibleRepositoryPaths.contains) ?? false
		}
	}

	/// A banner over the screen saying what an action did.
	public struct Notice: Equatable, Sendable {
		public var icon: String
		public var title: String
		public var subtitle: String?
		/// A saved file the banner offers to show in Finder.
		public var fileURL: URL?

		public init(icon: String, title: String, subtitle: String? = nil, fileURL: URL? = nil) {
			self.icon = icon
			self.title = title
			self.subtitle = subtitle
			self.fileURL = fileURL
		}
	}

	public enum Action: Equatable {
		/// The pane is on screen beside `repositoryPath`'s terminal; runs until it leaves or shows
		/// another repository.
		case task(repositoryPath: String)
		case devicesLoaded([SimulatorDevice], storedSelection: String?)
		case devicesFailed(String)
		case deviceSelected(String)
		case bootButtonTapped
		case shutdownButtonTapped
		case transitionFinished(errorMessage: String?)
		case hardwareButtonTapped(SimulatorHardwareButton)
		case rotateButtonTapped(clockwise: Bool)
		/// Opens a closed iPhone Duo, or closes an open or partially open one.
		case foldButtonTapped
		/// Sets how far an iPhone Duo is open: the More menu's Hinge items.
		case foldSelected(SimulatorFold)
		case screenshotButtonTapped
		case screenshotSaved(URL)
		case screenshotFailed(String)
		case recordButtonTapped
		case recordingStarted(deviceId: String)
		case recordingSaved(SimulatorRecording, deviceId: String)
		case recordingFailed(String)
		case recordingDeviceIdsChanged(Set<String>)
		case memoryWarningButtonTapped
		case locationSelected(SimulatorLocationCommand)
		/// A feature (memory warning, location) did its thing, or failed with a message.
		case featureFinished(Notice?, errorMessage: String?)
		case showNoticeFileInFinderTapped
		case noticeDismissed
		case connectClaudeCodeButtonTapped
		case claudeCodeStatusChecked(Bool)
		case connectClaudeCodeFinished(errorMessage: String?)
		case errorDismissed
		case toggleVisibility(repositoryPath: String)
		case closeButtonTapped(repositoryPath: String)
		/// An MCP tool call touched `deviceId`: show it beside `repositoryPath`'s terminal.
		case activityReported(deviceId: String, repositoryPath: String)
		/// The repository on screen builds `projectPath` (`nil`: it has no Xcode project).
		case projectChanged(String?)
		case schemesLoaded([XcodeScheme], storedName: String?)
		case schemeSelected(String)
		case runButtonTapped
		case delegate(Delegate)

		public enum Delegate: Equatable {
			/// Type `command` into the repository's run tab, named `title`, replacing what ran
			/// there before.
			case runRequested(command: String, title: String)
		}
	}

	private enum CancelId {
		case polling
		case recordings
		case notice
		case schemes
	}

	@Dependency(SimulatorClient.self)
	private var simulatorClient

	@Dependency(\.continuousClock)
	private var clock

	public init() {}

	/// Shows `notice` for six seconds, or until dismissed or replaced.
	private func show(_ notice: Notice, in state: inout State) -> Effect<Action> {
		state.notice = notice
		return .run { [clock] send in
			try await clock.sleep(for: .seconds(6))
			await send(.noticeDismissed)
		}
		.cancellable(id: CancelId.notice, cancelInFlight: true)
	}

	/// Folds or unfolds the selected iPhone Duo to `fold`, then reloads the devices so the pane
	/// shows the panel it moved to straight away. It shows as a transition: `dtuhidd` can take
	/// many seconds to take the report while the guest is busy.
	private func setFold(_ fold: SimulatorFold, state: inout State) -> Effect<Action> {
		guard
			let device = state.selectedDevice, device.isBooted, let current = device.fold, current != fold,
			state.transitioningDeviceId == nil
		else {
			return .none
		}
		state.transitioningDeviceId = device.id
		state.errorMessage = nil
		return .run { [simulatorClient, repositoryPath = state.repositoryPath] send in
			do {
				try await simulatorClient.setFold(device, fold)
				let devices = try await simulatorClient.devices()
				await send(.devicesLoaded(devices, storedSelection: simulatorClient.selectedDeviceId(repositoryPath)))
				await send(.transitionFinished(errorMessage: nil))
			}
			catch {
				await send(.transitionFinished(errorMessage: error.localizedDescription))
			}
		}
	}

	public var body: some Reducer<State, Action> {
		Reduce { state, action in
			switch action {
			case let .task(repositoryPath):
				if state.repositoryPath != repositoryPath {
					// Another repository's device: shown once the first poll reads it, rather than
					// the previous repository's for a moment.
					state.repositoryPath = repositoryPath
					state.selectedDeviceId = nil
					state.errorMessage = nil
				}
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
								await send(.devicesLoaded(
									devices,
									storedSelection: simulatorClient.selectedDeviceId(repositoryPath)
								))
							}
							catch {
								await send(.devicesFailed(error.localizedDescription))
							}
							try await clock.sleep(for: .seconds(1.5))
						}
					}
					.cancellable(id: CancelId.polling, cancelInFlight: true),
					.run { [simulatorClient] send in
						for await ids in simulatorClient.recordingDeviceIds() {
							await send(.recordingDeviceIdsChanged(ids))
						}
					}
					.cancellable(id: CancelId.recordings, cancelInFlight: true)
				)

			case let .devicesLoaded(devices, storedSelection):
				let previouslyBooted = state.selectedDevice?.isBooted ?? false
				state.devices = devices
				state.hasLoadedDevices = true
				state.loadErrorMessage = nil

				// The stored selection is the repository's, shared with the MCP tools its terminal's
				// `claude` calls: they move it to the device they act on, and the pane follows.
				let selection = storedSelection.flatMap { id in devices.first { $0.id == id } }
					?? devices.first(where: \.isBooted)
					?? devices.first
				state.selectedDeviceId = selection?.id

				var effects: [Effect<Action>] = []
				if let selection, selection.id != storedSelection {
					effects.append(.run { [simulatorClient, repositoryPath = state.repositoryPath] _ in
						simulatorClient.selectDevice(selection.id, repositoryPath)
					})
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
				return .run { [simulatorClient, repositoryPath = state.repositoryPath] _ in
					simulatorClient.selectDevice(id, repositoryPath)
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
				// waiting for the next poll. When the app does not support the orientation the
				// device turns but the screen does not, which a notice says.
				return .run { [simulatorClient, repositoryPath = state.repositoryPath] send in
					do {
						let rotation = try await simulatorClient.rotate(device.id, clockwise)
						let devices = try await simulatorClient.devices()
						await send(.devicesLoaded(devices, storedSelection: simulatorClient.selectedDeviceId(repositoryPath)))
						if !rotation.interfaceFollowed {
							let notice = Notice(
								icon: clockwise ? "rotate.right" : "rotate.left",
								title: "Turned to \(rotation.orientation.label)",
								subtitle: "The app or home screen doesn't support it, so the screen stays \(rotation.interfaceRotation.label)."
							)
							await send(.featureFinished(notice, errorMessage: nil))
						}
					}
					catch {
						await send(.transitionFinished(errorMessage: error.localizedDescription))
					}
				}

			case .foldButtonTapped:
				guard let fold = state.selectedDevice?.fold else {
					return .none
				}
				return setFold(fold.toggled, state: &state)

			case let .foldSelected(fold):
				return setFold(fold, state: &state)

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
				return show(Notice(icon: "camera.fill", title: "Screenshot saved", subtitle: url.lastPathComponent, fileURL: url), in: &state)

			case let .screenshotFailed(message):
				state.isSavingScreenshot = false
				state.errorMessage = "Could not save the screenshot: \(message)"
				return .none

			case .recordButtonTapped:
				guard let device = state.selectedDevice, !state.isTogglingRecording else {
					return .none
				}
				// Stopping works on a device that shut down meanwhile; starting needs it booted.
				let isRecording = state.isRecordingSelectedDevice
				guard isRecording || device.isBooted else {
					return .none
				}
				state.isTogglingRecording = true
				state.errorMessage = nil
				return .run { [simulatorClient] send in
					do {
						if isRecording {
							try await send(.recordingSaved(simulatorClient.stopRecording(device), deviceId: device.id))
						}
						else {
							try await simulatorClient.startRecording(device)
							await send(.recordingStarted(deviceId: device.id))
						}
					}
					catch {
						await send(.recordingFailed(error.localizedDescription))
					}
				}

			case let .recordingStarted(deviceId):
				state.isTogglingRecording = false
				state.recordingDeviceIds.insert(deviceId)
				return .none

			case let .recordingSaved(recording, deviceId):
				state.isTogglingRecording = false
				state.recordingDeviceIds.remove(deviceId)
				let title = recording.endedEarly == nil ? "Recording saved" : "Recording had already stopped"
				return show(Notice(icon: "record.circle", title: title, subtitle: recording.url.lastPathComponent, fileURL: recording.url), in: &state)

			case let .recordingFailed(message):
				state.isTogglingRecording = false
				state.errorMessage = message
				return .none

			case let .recordingDeviceIdsChanged(ids):
				state.recordingDeviceIds = ids
				return .none

			case .memoryWarningButtonTapped:
				guard let device = state.selectedDevice, device.isBooted else {
					return .none
				}
				return .run { [simulatorClient] send in
					do {
						try await simulatorClient.simulateMemoryWarning(device.id)
						await send(.featureFinished(Notice(icon: "memorychip", title: "Memory warning sent"), errorMessage: nil))
					}
					catch {
						await send(.featureFinished(nil, errorMessage: error.localizedDescription))
					}
				}

			case let .locationSelected(command):
				guard let device = state.selectedDevice, device.isBooted else {
					return .none
				}
				let title = switch command {
				case .clear:
					"Simulated location cleared"
				case let .scenario(name):
					"Location: \(name)"
				case let .set(coordinate):
					SimulatorLocationCommand.places.first { $0.coordinate == coordinate }.map { "Location: \($0.name)" } ?? "Location set"
				case .route:
					"Location set"
				}
				return .run { [simulatorClient] send in
					do {
						try await simulatorClient.setLocation(device.id, command)
						await send(.featureFinished(Notice(icon: "location.fill", title: title), errorMessage: nil))
					}
					catch {
						await send(.featureFinished(nil, errorMessage: error.localizedDescription))
					}
				}

			case let .featureFinished(notice, errorMessage):
				state.errorMessage = errorMessage
				guard let notice else {
					return .none
				}
				return show(notice, in: &state)

			case .showNoticeFileInFinderTapped:
				guard let url = state.notice?.fileURL else {
					return .none
				}
				state.notice = nil
				return .merge(
					.cancel(id: CancelId.notice),
					.run { [simulatorClient] _ in await simulatorClient.revealInFinder(url) }
				)

			case .noticeDismissed:
				state.notice = nil
				return .cancel(id: CancelId.notice)

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

			case let .toggleVisibility(repositoryPath):
				state.$visibleRepositoryPaths.withLock { paths in
					if paths.contains(repositoryPath) {
						paths.removeAll { $0 == repositoryPath }
					}
					else {
						paths.append(repositoryPath)
					}
				}
				return .none

			case let .closeButtonTapped(repositoryPath):
				state.$visibleRepositoryPaths.withLock { $0.removeAll { $0 == repositoryPath } }
				return .none

			case let .activityReported(deviceId, repositoryPath):
				if !state.isVisible(in: repositoryPath) {
					state.$visibleRepositoryPaths.withLock { $0.append(repositoryPath) }
				}
				// Another repository's call moved that repository's device, not the one on screen.
				if repositoryPath == state.repositoryPath, state.devices.contains(where: { $0.id == deviceId }) {
					state.selectedDeviceId = deviceId
				}
				return .none

			case let .projectChanged(projectPath):
				state.projectPath = projectPath
				guard let projectPath else {
					state.schemes = []
					state.selectedSchemeName = nil
					state.hasLoadedSchemes = true
					return .cancel(id: CancelId.schemes)
				}
				state.hasLoadedSchemes = false
				return .run { [simulatorClient] send in
					let schemes = await simulatorClient.runnableSchemes(projectPath)
					let fileName = (projectPath as NSString).lastPathComponent
					await send(.schemesLoaded(schemes, storedName: simulatorClient.storedSchemeName(fileName)))
				}
				.cancellable(id: CancelId.schemes, cancelInFlight: true)

			case let .schemesLoaded(schemes, storedName):
				state.schemes = schemes
				state.hasLoadedSchemes = true
				// The one last run, else the one named after the workspace — the app itself,
				// typically, among its extensions' schemes — else the first.
				let baseName = state.projectPath.map { (($0 as NSString).lastPathComponent as NSString).deletingPathExtension }
				let names = schemes.map(\.name)
				state.selectedSchemeName = [storedName, state.selectedSchemeName, baseName]
					.compactMap { $0 }
					.first(where: names.contains)
					?? names.first
				return .none

			case let .schemeSelected(name):
				state.selectedSchemeName = name
				guard let projectPath = state.projectPath else {
					return .none
				}
				return .run { [simulatorClient] _ in
					simulatorClient.storeSchemeName(name, (projectPath as NSString).lastPathComponent)
				}

			case .runButtonTapped:
				guard let projectPath = state.projectPath, let scheme = state.selectedScheme, let device = state.selectedDevice else {
					return .none
				}
				state.errorMessage = nil
				var effects: [Effect<Action>] = [
					.run { [simulatorClient] send in
						simulatorClient.storeSchemeName(scheme.name, (projectPath as NSString).lastPathComponent)
						do {
							let command = try simulatorClient.runCommand(projectPath, scheme, device)
							await send(.delegate(.runRequested(command: command, title: scheme.name)))
						}
						catch {
							await send(.featureFinished(nil, errorMessage: "Could not run \(scheme.name): \(error.localizedDescription)"))
						}
					},
				]
				// Booted while the app builds, rather than by the script once the build is done.
				if device.state == .shutdown, state.transitioningDeviceId == nil {
					effects.append(.send(.bootButtonTapped))
				}
				return .merge(effects)

			case .delegate:
				return .none
			}
		}
	}
}
