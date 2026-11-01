import ComposableArchitecture
import CoreGraphics
import Foundation
import Testing
@testable import SimulatorFeature

@Suite("Run on the simulator")
struct SimulatorRunTests {
	// MARK: - Schemes

	private static func scheme(launching name: String?, inLaunchAction: Bool = true) -> Data {
		let reference = name.map {
			"""
			<BuildableReference BuildableIdentifier = "primary" BuildableName = "\($0)" BlueprintName = "X"/>
			"""
		} ?? ""
		let runnable = "<BuildableProductRunnable runnableDebuggingMode = \"0\">\(reference)</BuildableProductRunnable>"
		return Data("""
		<?xml version="1.0" encoding="UTF-8"?>
		<Scheme version = "1.7">
		   <BuildAction>
		      <BuildActionEntries>
		         <BuildActionEntry>
		            <BuildableReference BuildableName = "Framework.framework"/>
		         </BuildActionEntry>
		      </BuildActionEntries>
		   </BuildAction>
		   <TestAction>
		      <MacroExpansion>
		         <BuildableReference BuildableName = "Other.app"/>
		      </MacroExpansion>
		   </TestAction>
		   \(inLaunchAction ? "<LaunchAction buildConfiguration = \"Debug\">\(runnable)</LaunchAction>" : "<ProfileAction>\(runnable)</ProfileAction>")
		</Scheme>
		""".utf8)
	}

	@Test("a scheme's runnable app is what its Run action launches")
	func runnableProductOfLaunchAction() {
		#expect(XcodeSchemeScanner.runnableProductName(inScheme: Self.scheme(launching: "MyApp.app")) == "MyApp.app")
	}

	@Test("schemes that launch nothing, or not an app, are not runnable")
	func nonAppSchemesAreSkipped() {
		#expect(XcodeSchemeScanner.runnableProductName(inScheme: Self.scheme(launching: nil)) == nil)
		#expect(XcodeSchemeScanner.runnableProductName(inScheme: Self.scheme(launching: "Tool")) == nil)
		#expect(XcodeSchemeScanner.runnableProductName(inScheme: Self.scheme(launching: "App.app", inLaunchAction: false)) == nil)
	}

	@Test("a workspace's projects resolve against nested groups")
	func workspaceProjectPaths() {
		let contents = Data("""
		<?xml version="1.0" encoding="UTF-8"?>
		<Workspace version = "1.0">
		   <FileRef location = "group:MyApp/MyApp.xcodeproj"></FileRef>
		   <FileRef location = "group:README.md"></FileRef>
		   <Group location = "container:" name = "Dependencies">
		      <FileRef location = "group:Tuist/Facebook.xcodeproj"></FileRef>
		      <Group location = "group:Nested">
		         <FileRef location = "group:../Inner.xcodeproj"></FileRef>
		      </Group>
		      <Group name = "Folder only">
		         <FileRef location = "group:Plain.xcodeproj"></FileRef>
		      </Group>
		   </Group>
		   <FileRef location = "absolute:/elsewhere/Other.xcodeproj"></FileRef>
		</Workspace>
		""".utf8)

		let paths = XcodeSchemeScanner.projectPaths(inWorkspaceContents: contents, workspaceDirectory: "/repo/ios")

		#expect(paths == [
			"/repo/ios/MyApp/MyApp.xcodeproj",
			"/repo/ios/Tuist/Facebook.xcodeproj",
			"/repo/ios/Inner.xcodeproj",
			"/repo/ios/Plain.xcodeproj",
			"/elsewhere/Other.xcodeproj",
		])
	}

	@Test("the scanner reads shared and user schemes of the workspace's projects")
	func scannerFindsRunnableSchemes() throws {
		let root = FileManager.default.temporaryDirectory.appending(component: "SchemeScan-\(UUID().uuidString)")
		defer { try? FileManager.default.removeItem(at: root) }
		let workspace = root.appending(component: "App.xcworkspace")
		let project = root.appending(component: "App/App.xcodeproj")
		let shared = project.appending(component: "xcshareddata/xcschemes")
		let user = project.appending(component: "xcuserdata/tester.xcuserdatad/xcschemes")
		for folder in [workspace, shared, user] {
			try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		}
		try Data(#"<Workspace><FileRef location = "group:App/App.xcodeproj"/></Workspace>"#.utf8)
			.write(to: workspace.appending(component: "contents.xcworkspacedata"))
		try Self.scheme(launching: "App.app").write(to: shared.appending(component: "App.xcscheme"))
		try Self.scheme(launching: "App.app").write(to: shared.appending(component: "Widgets.xcscheme"))
		try Self.scheme(launching: "Kit.framework").write(to: shared.appending(component: "Kit.xcscheme"))
		try Self.scheme(launching: "Debug.app").write(to: user.appending(component: "app debug.xcscheme"))
		try Self.scheme(launching: "Other.app").write(to: user.appending(component: "App.xcscheme"))

		let scan = XcodeSchemeScanner.scanSchemeFiles(in: workspace.path(percentEncoded: false), userName: "tester")

		#expect(scan.foundSchemeFiles)
		#expect(scan.schemes == [
			XcodeScheme(name: "App", productName: "App.app"),
			XcodeScheme(name: "app debug", productName: "Debug.app"),
			XcodeScheme(name: "Widgets", productName: "App.app"),
		])
	}

	@Test("a project with no scheme files is told from one whose schemes run nothing")
	func noSchemeFiles() throws {
		let project = FileManager.default.temporaryDirectory.appending(component: "NoSchemes-\(UUID().uuidString).xcodeproj")
		defer { try? FileManager.default.removeItem(at: project) }
		try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)

		let scan = XcodeSchemeScanner.scanSchemeFiles(in: project.path(percentEncoded: false), userName: "tester")

		#expect(!scan.foundSchemeFiles)
		#expect(scan.schemes.isEmpty)
	}

	@Test("xcodebuild -list's schemes are read for a project and for a workspace")
	func listedSchemeNames() {
		let project = Data(#"{"project":{"configurations":["Debug"],"name":"App","schemes":["App","Kit"],"targets":["App"]}}"#.utf8)
		let workspace = Data(#"{"workspace":{"name":"App","schemes":["App"]}}"#.utf8)

		#expect(XcodeSchemeScanner.schemeNames(inListJSON: project) == ["App", "Kit"])
		#expect(XcodeSchemeScanner.schemeNames(inListJSON: workspace) == ["App"])
		#expect(XcodeSchemeScanner.schemeNames(inListJSON: Data("xcodebuild: error".utf8)).isEmpty)
	}

	// MARK: - Command

	@Test("words with shell syntax are single-quoted, plain ones left bare")
	func shellQuoting() {
		#expect(SimulatorRunCommand.shellQuoted("/repo/ios/App.xcworkspace") == "/repo/ios/App.xcworkspace")
		#expect(SimulatorRunCommand.shellQuoted("iPhone 17 Pro") == "'iPhone 17 Pro'")
		#expect(SimulatorRunCommand.shellQuoted("it's $HOME") == #"'it'\''s $HOME'"#)
		#expect(SimulatorRunCommand.shellQuoted("") == "''")
		#expect(SimulatorRunCommand.shellQuoted("Žluťoučký") == "'Žluťoučký'")
	}

	@Test("the command passes the project, scheme, product and destination to the script")
	func command() {
		let device = SimulatorDevice(
			id: "ABC-123",
			name: "iPhone 17 Pro",
			runtimeName: "iOS 27.0",
			state: .booted,
			screenPixelSize: CGSize(width: 1206, height: 2622),
			screenScale: 3
		)
		let command = SimulatorRunCommand.command(
			scriptPath: "/Users/me/Library/Application Support/bc/Scripts/run-ios-app.sh",
			projectPath: "/repo/ios/App.xcworkspace",
			scheme: XcodeScheme(name: "App", productName: "App.app"),
			destination: .simulator(device)
		)

		#expect(command == "/bin/bash '/Users/me/Library/Application Support/bc/Scripts/run-ios-app.sh' /repo/ios/App.xcworkspace App App.app simulator ABC-123 'iPhone 17 Pro'")

		let madeUp = SimulatorRunCommand.command(
			scriptPath: "/s.sh",
			projectPath: "/repo/App.xcodeproj",
			scheme: XcodeScheme(name: "App", productName: nil),
			destination: .simulator(device)
		)
		#expect(madeUp == "/bin/bash /s.sh /repo/App.xcodeproj App '' simulator ABC-123 'iPhone 17 Pro'")

		let phone = PhysicalDevice(id: "00008160-0014", name: "Alex's iPhone", model: "iPhone 18 Pro", osVersion: "27.0.1", kind: .iPhone, isAvailable: true)
		let onDevice = SimulatorRunCommand.command(
			scriptPath: "/s.sh",
			projectPath: "/repo/App.xcodeproj",
			scheme: XcodeScheme(name: "App", productName: "App.app"),
			destination: .device(phone)
		)
		#expect(onDevice == #"/bin/bash /s.sh /repo/App.xcodeproj App App.app device 00008160-0014 'Alex'\''s iPhone'"#)

		var twoLines = phone
		twoLines.name = "Alex's\niPhone"
		let flattened = SimulatorRunCommand.command(
			scriptPath: "/s.sh",
			projectPath: "/repo/App.xcodeproj",
			scheme: XcodeScheme(name: "App", productName: "App.app"),
			destination: .device(twoLines)
		)
		#expect(flattened == #"/bin/bash /s.sh /repo/App.xcodeproj App App.app device 00008160-0014 'Alex'\''s iPhone'"#)
	}

	// MARK: - Devices

	@Test("devicectl's list gives the paired iPhones and iPads, reachable ones first")
	func physicalDevicesFromDevicectl() throws {
		let json = Data("""
		{"info": {"outcome": "success"}, "result": {"devices": [
		  {"identifier": "D13C", "hardwareProperties": {"udid": "00008150-AAA", "platform": "iOS", "deviceType": "iPhone",
		    "marketingName": "iPhone 17 Pro", "reality": "physical"},
		   "deviceProperties": {"name": "Backup iPhone", "osVersionNumber": "27.0"},
		   "connectionProperties": {"pairingState": "paired", "tunnelState": "unavailable"}},
		  {"identifier": "4838", "hardwareProperties": {"udid": "00008160-BBB", "platform": "iOS", "deviceType": "iPhone",
		    "marketingName": "iPhone 18 Pro", "reality": "physical"},
		   "deviceProperties": {"name": "Work iPhone", "osVersionNumber": "27.0.1"},
		   "connectionProperties": {"pairingState": "paired", "transportType": "wired", "tunnelState": "connected"}},
		  {"identifier": "EFB3", "hardwareProperties": {"udid": "00008130-CCC", "platform": "iOS", "deviceType": "iPad",
		    "marketingName": "iPad Air", "reality": "physical"},
		   "deviceProperties": {"name": "Studio iPad"},
		   "connectionProperties": {"pairingState": "paired", "transportType": "localNetwork", "tunnelState": "disconnected"}},
		  {"identifier": "UNPR", "hardwareProperties": {"udid": "00008110-DDD", "platform": "iOS", "deviceType": "iPhone",
		    "marketingName": "iPhone 13", "reality": "physical"},
		   "deviceProperties": {"name": "Borrowed"},
		   "connectionProperties": {"pairingState": "unpaired", "transportType": "wired"}},
		  {"identifier": "ODD1", "hardwareProperties": {"udid": "0000 $(id)", "platform": "iOS", "deviceType": "iPhone",
		    "reality": "physical"}, "deviceProperties": {"name": "Odd"}},
		  {"identifier": "WTCH", "hardwareProperties": {"udid": "00008301-EEE", "platform": "watchOS", "deviceType": "appleWatch",
		    "reality": "physical"}, "deviceProperties": {"name": "Watch"}},
		  {"identifier": "SIM1", "hardwareProperties": {"udid": "FEDDF6FF", "platform": "iOS", "deviceType": "iPhone",
		    "marketingName": "iPhone 17", "reality": "simulated"}, "deviceProperties": {"name": "iPhone 17"}}
		]}}
		""".utf8)

		let devices = try PhysicalDeviceList.devices(inListJSON: json)

		#expect(devices == [
			PhysicalDevice(id: "00008130-CCC", name: "Studio iPad", model: "iPad Air", osVersion: nil, kind: .iPad, isAvailable: true),
			PhysicalDevice(id: "00008160-BBB", name: "Work iPhone", model: "iPhone 18 Pro", osVersion: "27.0.1", kind: .iPhone, isAvailable: true),
			PhysicalDevice(id: "00008150-AAA", name: "Backup iPhone", model: "iPhone 17 Pro", osVersion: "27.0", kind: .iPhone, isAvailable: false),
			PhysicalDevice(id: "00008110-DDD", name: "Borrowed", model: "iPhone 13", osVersion: nil, kind: .iPhone, isAvailable: false, isPaired: false),
		])
		// Not "none paired": the menu says the list could not be read.
		#expect(throws: PhysicalDeviceList.Failure.self) {
			try PhysicalDeviceList.devices(inListJSON: Data("devicectl: error".utf8))
		}
	}

	@Test("the script is valid bash")
	func scriptParses() throws {
		let url = FileManager.default.temporaryDirectory.appending(component: "run-\(UUID().uuidString).sh")
		defer { try? FileManager.default.removeItem(at: url) }
		try SimulatorRunCommand.script.write(to: url, atomically: true, encoding: .utf8)
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/bin/bash")
		process.arguments = ["-n", url.path(percentEncoded: false)]
		try process.run()
		process.waitUntilExit()
		#expect(process.terminationStatus == 0)
		#expect(SimulatorRunCommand.script.hasPrefix("#!/bin/bash\n"))
	}
}

@MainActor
struct SimulatorPaneRunTests {
	private nonisolated static let device = SimulatorDevice(
		id: "A",
		name: "iPhone",
		runtimeName: "iOS 27.0",
		state: .booted,
		screenPixelSize: CGSize(width: 1206, height: 2622),
		screenScale: 3
	)

	private nonisolated static let schemes = [
		XcodeScheme(name: "App", productName: "App.app"),
		XcodeScheme(name: "Widgets", productName: "App.app"),
	]

	@Test("a project's schemes load with the one named after it chosen")
	func schemesLoadWithProjectNamedChosen() async {
		let store = TestStore(initialState: SimulatorPaneReducer.State()) {
			SimulatorPaneReducer()
		} withDependencies: {
			$0[SimulatorClient.self].runnableSchemes = { _ in [XcodeScheme(name: "Alpha", productName: "A.app")] + Self.schemes }
			$0[SimulatorClient.self].storedSchemeName = { _ in nil }
			$0[SimulatorClient.self].storedRunDeviceId = { _ in nil }
		}

		await store.send(.projectChanged("/repo/ios/App.xcworkspace")) {
			$0.projectPath = "/repo/ios/App.xcworkspace"
		}
		await store.receive(.runDeviceRestored(nil, projectPath: "/repo/ios/App.xcworkspace"))
		await store.receive(.schemesLoaded([XcodeScheme(name: "Alpha", productName: "A.app")] + Self.schemes, storedName: nil)) {
			$0.schemes = [XcodeScheme(name: "Alpha", productName: "A.app")] + Self.schemes
			$0.hasLoadedSchemes = true
			$0.selectedSchemeName = "App"
		}
	}

	@Test("the scheme and device last run win, and are looked up by the project's file name")
	func storedSchemeWins() async {
		let askedFor = LockIsolated<String?>(nil)
		let store = TestStore(initialState: SimulatorPaneReducer.State()) {
			SimulatorPaneReducer()
		} withDependencies: {
			$0[SimulatorClient.self].runnableSchemes = { _ in Self.schemes }
			$0[SimulatorClient.self].storedSchemeName = { name in
				askedFor.setValue(name)
				return "Widgets"
			}
			$0[SimulatorClient.self].storedRunDeviceId = { _ in "00008160-BBB" }
		}

		await store.send(.projectChanged("/worktrees/feature/ios/App.xcworkspace")) {
			$0.projectPath = "/worktrees/feature/ios/App.xcworkspace"
		}
		await store.receive(.runDeviceRestored("00008160-BBB", projectPath: "/worktrees/feature/ios/App.xcworkspace")) {
			$0.runDeviceId = "00008160-BBB"
		}
		await store.receive(.schemesLoaded(Self.schemes, storedName: "Widgets")) {
			$0.schemes = Self.schemes
			$0.hasLoadedSchemes = true
			$0.selectedSchemeName = "Widgets"
		}
		#expect(askedFor.value == "App.xcworkspace")
	}

	@Test("a repository without a project has nothing to run")
	func noProjectClearsSchemes() async {
		var initial = SimulatorPaneReducer.State()
		initial.projectPath = "/repo/App.xcodeproj"
		initial.schemes = Self.schemes
		initial.selectedSchemeName = "App"
		let store = TestStore(initialState: initial) {
			SimulatorPaneReducer()
		}

		await store.send(.projectChanged(nil)) {
			$0.projectPath = nil
			$0.schemes = []
			$0.selectedSchemeName = nil
			$0.hasLoadedSchemes = true
		}
		#expect(!store.state.canRun)
	}

	@Test("Run asks for the run tab with the command for the scheme and the shown device")
	func runRequestsTab() async {
		var initial = SimulatorPaneReducer.State()
		initial.projectPath = "/repo/App.xcworkspace"
		initial.schemes = Self.schemes
		initial.selectedSchemeName = "Widgets"
		initial.devices = [Self.device]
		initial.selectedDeviceId = "A"
		let stored = LockIsolated<[String: String]>([:])
		let store = TestStore(initialState: initial) {
			SimulatorPaneReducer()
		} withDependencies: {
			$0[SimulatorClient.self].storeSchemeName = { name, project in stored.withValue { $0[project] = name } }
			$0[SimulatorClient.self].runCommand = { project, scheme, destination in
				"run \(project) \(scheme.name) \(destination.id)"
			}
		}

		await store.send(.runButtonTapped)
		await store.receive(.delegate(.runRequested(command: "run /repo/App.xcworkspace Widgets A", title: "Widgets")))
		#expect(stored.value == ["App.xcworkspace": "Widgets"])
	}

	@Test("Run boots a shut-down device while the app builds")
	func runBootsShutDownDevice() async {
		var shutdown = Self.device
		shutdown.state = .shutdown
		var initial = SimulatorPaneReducer.State()
		initial.projectPath = "/repo/App.xcworkspace"
		initial.schemes = Self.schemes
		initial.selectedSchemeName = "App"
		initial.devices = [shutdown]
		initial.selectedDeviceId = "A"
		let booted = LockIsolated<[String]>([])
		let store = TestStore(initialState: initial) {
			SimulatorPaneReducer()
		} withDependencies: {
			$0[SimulatorClient.self].storeSchemeName = { _, _ in }
			$0[SimulatorClient.self].runCommand = { _, _, _ in "run" }
			$0[SimulatorClient.self].boot = { id in booted.withValue { $0.append(id) } }
		}
		store.exhaustivity = .off

		await store.send(.runButtonTapped)
		await store.finish()
		await store.skipReceivedActions()
		#expect(booted.value == ["A"])
	}

	private nonisolated static let phone = PhysicalDevice(
		id: "00008160-BBB",
		name: "Work iPhone",
		model: "iPhone 18 Pro",
		osVersion: "27.0.1",
		kind: .iPhone,
		isAvailable: true
	)

	private static func readyToRun() -> SimulatorPaneReducer.State {
		var state = SimulatorPaneReducer.State()
		state.projectPath = "/repo/App.xcworkspace"
		state.schemes = Self.schemes
		state.selectedSchemeName = "App"
		state.devices = [Self.device]
		state.selectedDeviceId = "A"
		return state
	}

	@Test("a picked device is what Run builds for, and is remembered for the project")
	func pickedDeviceIsTheDestination() async {
		var initial = Self.readyToRun()
		initial.physicalDevices = [Self.phone]
		let stored = LockIsolated<[String]>([])
		let store = TestStore(initialState: initial) {
			SimulatorPaneReducer()
		} withDependencies: {
			$0[SimulatorClient.self].storeRunDeviceId = { id, project in stored.withValue { $0.append("\(project): \(id ?? "simulator")") } }
		}

		#expect(store.state.runDestination == .simulator(Self.device))
		await store.send(.runDestinationSelected(deviceId: Self.phone.id)) {
			$0.runDeviceId = Self.phone.id
		}
		#expect(store.state.runDestination == .device(Self.phone))

		await store.send(.runDestinationSelected(deviceId: nil)) {
			$0.runDeviceId = nil
		}
		#expect(store.state.runDestination == .simulator(Self.device))
		#expect(stored.value == ["App.xcworkspace: 00008160-BBB", "App.xcworkspace: simulator"])
	}

	@Test("a picked device out of reach disables Run rather than falling back to the simulator")
	func unreachableDeviceDisablesRun() {
		var state = Self.readyToRun()
		state.runDeviceId = Self.phone.id
		#expect(!state.canRun)

		var away = Self.phone
		away.isAvailable = false
		state.physicalDevices = [away]
		#expect(!state.canRun)

		state.physicalDevices = [Self.phone]
		#expect(state.canRun)
	}

	@Test("Run on a device leaves the shut-down simulator alone")
	func runOnDeviceDoesNotBootTheSimulator() async {
		var initial = Self.readyToRun()
		initial.devices[0].state = .shutdown
		initial.physicalDevices = [Self.phone]
		initial.runDeviceId = Self.phone.id
		let store = TestStore(initialState: initial) {
			SimulatorPaneReducer()
		} withDependencies: {
			$0[SimulatorClient.self].storeSchemeName = { _, _ in }
			$0[SimulatorClient.self].runCommand = { _, scheme, destination in
				guard case let .device(device) = destination else {
					return "wrong destination"
				}
				return "run \(scheme.name) \(device.id)"
			}
		}

		await store.send(.runButtonTapped)
		await store.receive(.delegate(.runRequested(command: "run App 00008160-BBB", title: "App")))
	}

	@Test("paired devices are polled while the pane is on screen, and only a change or failure is sent")
	func physicalDevicesArePolled() async {
		struct Unavailable: LocalizedError {
			var errorDescription: String? {
				"devicectl is missing"
			}
		}
		let reads = LockIsolated<[Result<[PhysicalDevice], Unavailable>]>([
			.success([]), .success([Self.phone]), .success([Self.phone]), .failure(Unavailable()), .success([]),
		])
		let clock = TestClock()
		let store = TestStore(initialState: SimulatorPaneReducer.State()) {
			SimulatorPaneReducer()
		} withDependencies: {
			$0[SimulatorClient.self].devices = { [] }
			$0[SimulatorClient.self].selectedDeviceId = { _ in nil }
			$0[SimulatorClient.self].isClaudeCodeConnected = { true }
			$0[SimulatorClient.self].recordingDeviceIds = { .finished }
			$0[SimulatorClient.self].physicalDevices = {
				try reads.withValue { $0.count > 1 ? $0.removeFirst() : $0[0] }.get()
			}
			$0.continuousClock = clock
		}
		store.exhaustivity = .off(showSkippedAssertions: false)

		let task = await store.send(.task(repositoryPath: "/repos/app"))
		await clock.advance(by: .seconds(3))
		await store.receive(.physicalDevicesLoaded([Self.phone])) {
			$0.physicalDevices = [Self.phone]
		}
		await clock.advance(by: .seconds(3))
		await clock.advance(by: .seconds(3))
		await store.receive(.physicalDevicesFailed("devicectl is missing")) {
			$0.physicalDevicesError = "devicectl is missing"
		}
		await clock.advance(by: .seconds(3))
		await store.receive(.physicalDevicesLoaded([])) {
			$0.physicalDevices = []
			$0.physicalDevicesError = nil
		}
		await task.cancel()
	}

	@Test("a device read for a project the pane has moved on from is dropped")
	func staleRestoredDeviceIsDropped() async {
		var initial = SimulatorPaneReducer.State()
		initial.projectPath = "/repo/Other.xcworkspace"
		let store = TestStore(initialState: initial) {
			SimulatorPaneReducer()
		}

		await store.send(.runDeviceRestored(Self.phone.id, projectPath: "/repo/App.xcworkspace"))
		#expect(store.state.runDeviceId == nil)
	}
}
