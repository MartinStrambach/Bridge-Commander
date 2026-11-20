import AppUI
import ComposableArchitecture
import Foundation
import Testing
import ToolsIntegration
@testable import RepositoryFeature

@Suite("XcodeGen menu")
@MainActor
struct XcodeGenButtonTests {
	private struct CommandError: LocalizedError {
		var errorDescription: String? { "Spec validation error" }
	}

	@Test("generate runs xcodegen in the Xcode project path with the XcodeGen settings")
	func generateRunsInIOSFolder() async {
		let received = LockIsolated<(XcodeGenAction, String, String, GeneratorRunMode)?>(nil)
		let store = makeStore {
			$0[XcodeGenClient.self].run = { action, path, misePath, runMode in
				received.setValue((action, path, misePath, runMode))
				return .success("Created project")
			}
		}
		store.state.$openXcodeAfterGenerate.withLock { $0 = false }
		store.state.$misePath.withLock { $0 = "/opt/mise" }
		store.state.$xcodeGenRunMode.withLock { $0 = .native }

		await store.send(.generateTapped) {
			$0.runningAction = .generate
		}
		await store.receive(\.actionCompleted) {
			$0.runningAction = nil
		}

		#expect(received.value?.0 == .generate)
		#expect(received.value?.1 == "/repos/app/ios")
		#expect(received.value?.2 == "/opt/mise")
		#expect(received.value?.3 == .native)
	}

	@Test("a generate opens the project afterwards when the setting asks")
	func generateOpensProject() async {
		let opened = LockIsolated<[String]>([])
		let preferences = LockIsolated<[XcodeFilePreference]>([])
		// The group's choice of workspace or project, as its Xcode button opens.
		let store = makeStore(xcodeFilePreference: .project) {
			$0[XcodeGenClient.self].run = { _, _, _, _ in .success("") }
			$0[XcodeClient.self].findXcodeProject = { _, _, preference in
				preferences.withValue { $0.append(preference) }
				return "/repos/app/ios/App.xcodeproj"
			}
			$0[XcodeClient.self].openProject = { path in opened.withValue { $0.append(path) } }
		}
		store.state.$openXcodeAfterGenerate.withLock { $0 = true }

		await store.send(.generateUsingCacheTapped) {
			$0.runningAction = .generateUsingCache
		}
		await store.receive(\.actionCompleted) {
			$0.runningAction = nil
		}

		#expect(opened.value == ["/repos/app/ios/App.xcodeproj"])
		#expect(preferences.value == [.project])
	}

	@Test("Edit Spec reports a folder with no spec")
	func editSpecWithoutSpec() async {
		let store = makeStore {
			$0[XcodeGenClient.self].openSpec = { _, _ in throw XcodeGenSpecNotFoundError() }
		}

		await store.send(.editSpecTapped)
		await store.receive(\.editSpecFailed) {
			$0.alert = .init(
				title: "Could Not Open the XcodeGen Spec",
				message: "No project.yml or project.json found in the Xcode project path.",
				isError: true
			)
		}
	}

	@Test("the spec summary never opens Xcode and shows its output")
	func summaryShowsOutput() async {
		let store = makeStore {
			$0[XcodeGenClient.self].run = { _, _, _, _ in .success("Targets: App") }
		}
		store.state.$openXcodeAfterGenerate.withLock { $0 = true }

		await store.send(.dumpSummaryTapped) {
			$0.runningAction = .dumpSummary
		}
		await store.receive(\.actionCompleted) {
			$0.runningAction = nil
			$0.alert = .init(title: "XcodeGen Spec Summary", message: "Targets: App", isError: false)
		}
	}

	@Test("a failed generate reports the error and stops the progress")
	func failedGenerateReportsError() async {
		let store = makeStore {
			$0[XcodeGenClient.self].run = { _, _, _, _ in .failure(CommandError()) }
		}

		await store.send(.generateTapped) {
			$0.runningAction = .generate
		}
		await store.receive(\.actionCompleted) {
			$0.runningAction = nil
			$0.alert = .init(title: "XcodeGen Generate Failed", message: "Spec validation error", isError: true)
		}
	}

	@Test("a command is ignored while another runs")
	func ignoredWhileBusy() async {
		var state = XcodeGenButtonReducer.State(repositoryPath: "/repos/app", iosSubfolderPath: "ios")
		state.runningAction = .generate
		let store = TestStore(initialState: state) {
			XcodeGenButtonReducer()
		}

		await store.send(.dumpSummaryTapped)
	}

	@Test("a finished generate makes the row look for the Xcode project again")
	func generateRefreshesXcodeButton() async {
		let store = TestStore(
			initialState: RepositoryRowReducer.State(
				path: "/repos/app",
				name: "app",
				branchName: "main",
				supportsIOS: true,
				iosSubfolderPath: "ios",
				supportsXcodeGen: true
			)
		) {
			RepositoryRowReducer()
		} withDependencies: {
			$0[XcodeClient.self].findXcodeProject = { _, _, _ in "/repos/app/ios/App.xcodeproj" }
			$0[XcodeClient.self].projectGenerator = { _, _ in .xcodeGen }
		}
		store.exhaustivity = .off

		await store.send(.xcodeGenButton(.actionCompleted(.generate, .success(""))))
		await store.receive(\.xcodeButton.refresh)
		await store.receive(\.xcodeButton.foundProjectPath) {
			$0.xcodeButton.projectPath = "/repos/app/ios/App.xcodeproj"
		}
	}

	// MARK: - Helpers

	private func makeStore(
		xcodeFilePreference: XcodeFilePreference = .auto,
		_ dependencies: @escaping (inout DependencyValues) -> Void
	) -> TestStoreOf<XcodeGenButtonReducer> {
		TestStore(
			initialState: XcodeGenButtonReducer.State(
				repositoryPath: "/repos/app",
				iosSubfolderPath: "ios",
				xcodeFilePreference: xcodeFilePreference
			)
		) {
			XcodeGenButtonReducer()
		} withDependencies: {
			dependencies(&$0)
		}
	}
}
