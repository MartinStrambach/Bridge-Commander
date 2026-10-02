import AppUI
import ComposableArchitecture
import Foundation
import Testing
import ToolsIntegration
@testable import RepositoryFeature

@Suite("Xcode button project generation")
@MainActor
struct XcodeProjectButtonGenerationTests {
	private struct GenerationError: LocalizedError {
		var errorDescription: String? { "tuist install failed" }
	}

	@Test("every progress state reaches the button, in order, before the project opens")
	func progressArrivesInOrderBeforeOpening() async {
		// Progress used to be sent from a detached `Task` per state, so the last `.checking` could
		// land after `didOpenProject` and leave the button spinning with nothing running.
		let opened = LockIsolated<[String]>([])
		let store = makeStore {
			$0[XcodeClient.self].generateProject = { _, _, _, _, _, onStateChange in
				await onStateChange(.runningTi)
				await onStateChange(.runningTg)
				await onStateChange(.checking)
				return "/repos/app/App.xcworkspace"
			}
			$0[XcodeClient.self].openProject = { path in
				opened.withValue { $0.append(path) }
			}
		}

		await store.send(.openProject) {
			$0.alert = Self.generateAlert
		}
		await store.send(.alert(.presented(.confirmGenerate))) {
			$0.alert = nil
		}
		await store.receive(\.projectGenerationProgress) {
			$0.projectState = .runningTi
		}
		await store.receive(\.projectGenerationProgress) {
			$0.projectState = .runningTg
		}
		await store.receive(\.projectGenerationProgress) {
			$0.projectState = .checking
		}
		await store.receive(\.didGenerateProject) {
			$0.projectPath = "/repos/app/App.xcworkspace"
		}
		await store.receive(\.openProject) {
			$0.projectState = .opening
		}
		await store.receive(\.didOpenProject) {
			$0.projectState = .idle
		}

		#expect(opened.value == ["/repos/app/App.xcworkspace"])
	}

	@Test("a progress report has reached the button by the time the generator moves on")
	func progressLandsBeforeGeneratorContinues() async {
		// Progress used to be forwarded from a detached `Task` per state: nothing ordered it
		// against the generator's next step, so the last `.checking` could land after
		// `didOpenProject` and leave the button spinning. Awaiting the send rules that out.
		// The log is written when the reducer handles a report and when the generator resumes,
		// neither of which hops actors, so the order it records is the order things happened.
		let log = LockIsolated<[String]>([])
		var state = XcodeProjectButtonReducer.State(repositoryPath: "/repos/app", iosSubfolderPath: "ios/App")
		state.usesTuist = true
		let store = Store(initialState: state) {
			Reduce<XcodeProjectButtonReducer.State, XcodeProjectButtonReducer.Action> { _, action in
				if case let .projectGenerationProgress(progress) = action {
					log.withValue { $0.append("shown \(progress)") }
				}
				return .none
			}
			XcodeProjectButtonReducer()
		} withDependencies: {
			$0[XcodeClient.self].generateProject = { _, _, _, _, _, onStateChange in
				for progress in [XcodeProjectState.runningTi, .runningTg, .checking] {
					await onStateChange(progress)
					log.withValue { $0.append("resumed after \(progress)") }
				}
				// Succeed: a failure would present the error sheet, and a presentation keeps an
				// effect alive until it is dismissed, so `finish()` below would never return.
				return "/repos/app/App.xcworkspace"
			}
			$0[XcodeClient.self].openProject = { _ in }
		}

		store.send(.openProject)
		await store.send(.alert(.presented(.confirmGenerate))).finish()

		#expect(log.value == [
			"shown runningTi", "resumed after runningTi",
			"shown runningTg", "resumed after runningTg",
			"shown checking", "resumed after checking",
		])
	}

	@Test("generation passes the button's repository, subfolder and tuist settings through")
	func generationReceivesButtonSettings() async {
		let received = LockIsolated<(String, String, Bool, String, TuistRunMode)?>(nil)
		let store = makeStore {
			$0[XcodeClient.self].generateProject = { path, subfolder, shouldOpen, misePath, runMode, _ in
				received.setValue((path, subfolder, shouldOpen, misePath, runMode))
				throw GenerationError()
			}
		}
		store.state.$openXcodeAfterGenerate.withLock { $0 = false }
		store.state.$misePath.withLock { $0 = "/opt/mise" }
		store.state.$tuistRunMode.withLock { $0 = .native }
		store.exhaustivity = .off

		await store.send(.openProject)
		await store.send(.alert(.presented(.confirmGenerate)))
		await store.receive(\.generationFailed)

		let request = received.value
		#expect(request?.0 == "/repos/app")
		#expect(request?.1 == "ios/App")
		#expect(request?.2 == false)
		#expect(request?.3 == "/opt/mise")
		#expect(request?.4 == .native)
	}

	@Test("a failed generation stops the spinner and reports the error")
	func failedGenerationReportsError() async {
		let store = makeStore {
			$0[XcodeClient.self].generateProject = { _, _, _, _, _, onStateChange in
				await onStateChange(.runningTi)
				throw GenerationError()
			}
		}

		await store.send(.openProject) {
			$0.alert = Self.generateAlert
		}
		await store.send(.alert(.presented(.confirmGenerate))) {
			$0.alert = nil
		}
		await store.receive(\.projectGenerationProgress) {
			$0.projectState = .runningTi
		}
		await store.receive(\.generationFailed) {
			$0.projectState = .error("tuist install failed")
			$0.errorAlert = .init(
				title: "Project Generation Failed",
				message: "tuist install failed",
				isError: true
			)
		}
		#expect(store.state.projectState.isProcessing == false)
		#expect(store.state.projectPath == nil)
	}

	// MARK: - Helpers

	private static let generateAlert = AlertState<XcodeProjectButtonReducer.Action.Alert> {
		TextState("No Xcode Project Found")
	} actions: {
		ButtonState(role: .cancel) {
			TextState("Cancel")
		}
		ButtonState(action: .confirmGenerate) {
			TextState("Generate")
		}
	} message: {
		TextState("No Xcode project or workspace was found.\n\nWould you like to generate one?")
	}

	private func makeStore(
		_ dependencies: (inout DependencyValues) -> Void
	) -> TestStoreOf<XcodeProjectButtonReducer> {
		var state = XcodeProjectButtonReducer.State(repositoryPath: "/repos/app", iosSubfolderPath: "ios/App")
		state.usesTuist = true
		return TestStore(initialState: state) {
			XcodeProjectButtonReducer()
		} withDependencies: {
			dependencies(&$0)
		}
	}
}
