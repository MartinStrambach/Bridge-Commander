import ComposableArchitecture
import DependenciesTestSupport
import Foundation
@testable import HomerFeature
import Testing

@MainActor
@Suite("Homer process page", .dependencies)
struct HomerProcessDetailReducerTests {
	private static let baseURL = "https://homer.example.com"
	private let admin = HomerUser(username: "admin", role: "admin")

	private func state(_ process: HomerProcess? = nil, user: HomerUser? = nil) -> HomerProcessDetailReducer.State {
		var state = HomerProcessDetailReducer.State(baseURL: Self.baseURL, processId: process?.id ?? 7, user: user ?? admin)
		state.process = process
		return state
	}

	@Test("the page polls its run every 5 s")
	func polls() async {
		let clock = TestClock()
		let finished = HomerProcess(id: 7, status: .finished, agentName: "factory")
		let store = TestStore(initialState: state()) {
			HomerProcessDetailReducer()
		} withDependencies: {
			$0.continuousClock = clock
			$0[HomerProcessDetailClient.self].process = { baseURL, id in
				#expect(baseURL == Self.baseURL)
				#expect(id == 7)
				return finished
			}
		}

		await store.send(.task)
		await store.receive(\.processLoaded) {
			$0.process = finished
		}
		await clock.advance(by: .seconds(5))
		await store.receive(\.processLoaded)
		await store.skipInFlightEffects()
	}

	@Test("a failed run is asked whether it has a workflow, and Resume is offered when it does")
	func resumeNeedsWorkflow() async {
		let failed = HomerProcess(id: 7, status: .failed, agentName: "factory")
		let store = TestStore(initialState: state()) {
			HomerProcessDetailReducer()
		} withDependencies: {
			$0.continuousClock = ImmediateClock()
			$0[HomerProcessDetailClient.self].process = { _, _ in failed }
			$0[HomerProcessDetailClient.self].langGraphStatus = { _, _, graph in
				#expect(!graph)
				return HomerLangGraphStatus(label: "workflow", threadId: "t-1")
			}
		}

		await store.send(.processLoaded(processId: 7, .success(failed))) {
			$0.process = failed
			$0.langGraphProbe = .probing
		}
		#expect(!store.state.canResume)
		await store.receive(\.langGraphProbed) {
			$0.langGraphProbe = .found(label: "workflow")
		}
		#expect(store.state.canResume)
		#expect(!store.state.canKill)
		#expect(store.state.canRetry)
	}

	@Test("a run with no workflow is asked again once a command runs that the answer did not see")
	func probeAgainForNewCommand() async {
		var running = HomerProcess(id: 7, status: .working, agentName: "factory", currentCommand: "checkout")
		var initialState = state(running)
		initialState.langGraphProbe = .none(currentCommand: "checkout")
		let store = TestStore(initialState: initialState) {
			HomerProcessDetailReducer()
		} withDependencies: {
			$0[HomerProcessDetailClient.self].langGraphStatus = { _, _, _ in
				HomerLangGraphStatus(label: "workflow", threadId: "t-1")
			}
		}

		await store.send(.processLoaded(processId: 7, .success(running)))
		running.currentCommand = "workflow"
		await store.send(.processLoaded(processId: 7, .success(running))) {
			$0.process = running
			$0.langGraphProbe = .probing
		}
		await store.receive(\.langGraphProbed) {
			$0.langGraphProbe = .found(label: "workflow")
		}
		#expect(store.state.liveCommandIsWorkflow)
	}

	@Test("opening the workflow's execution polls its node states; closing it stops")
	func workflowPolledWhileShown() async {
		let clock = TestClock()
		let process = HomerProcess(
			id: 7,
			status: .finished,
			agentName: "factory",
			executions: [.init(label: "checkout", resultCode: 0), .init(label: "workflow", resultCode: 0)]
		)
		let status = HomerLangGraphStatus(label: "workflow", threadId: "t-1", nodeStates: ["plan": "done"])
		var initialState = state(process)
		initialState.langGraphProbe = .found(label: "workflow")
		let store = TestStore(initialState: initialState) {
			HomerProcessDetailReducer()
		} withDependencies: {
			$0.continuousClock = clock
			$0[HomerProcessDetailClient.self].langGraphStatus = { _, _, graph in
				#expect(graph)
				return status
			}
		}

		// Not the workflow's command: nothing to poll.
		await store.send(.executionToggled(index: 0)) {
			$0.expandedExecutions = [0]
		}
		await store.send(.executionToggled(index: 1)) {
			$0.expandedExecutions = [0, 1]
			$0.isPollingWorkflow = true
		}
		await store.receive(\.workflowLoaded) {
			$0.workflow = status
		}
		await clock.advance(by: .seconds(5))
		await store.receive(\.workflowLoaded)
		await store.send(.executionToggled(index: 1)) {
			$0.expandedExecutions = [0]
			$0.isPollingWorkflow = false
		}
		await clock.advance(by: .seconds(30))
	}

	@Test("a retry opens the new run on the page, and Back returns")
	func retryOpensNewRun() async {
		let clock = TestClock()
		let finished = HomerProcess(id: 7, status: .finished, agentName: "factory")
		let retried = HomerProcess(id: 8, status: .working, agentName: "factory")
		let store = TestStore(initialState: state(finished)) {
			HomerProcessDetailReducer()
		} withDependencies: {
			$0.continuousClock = clock
			$0[HomerClient.self].retryProcess = { _, id in
				#expect(id == 7)
				return 8
			}
			$0[HomerProcessDetailClient.self].process = { _, id in id == 8 ? retried : finished }
		}

		await store.send(.retryTapped) {
			$0.actionInFlight = .retry
		}
		await store.receive(\.actionFinished) {
			$0.actionInFlight = nil
		}
		await store.receive(\.processLinkTapped) {
			$0.backStack = [7]
			$0.processId = 8
			$0.process = nil
		}
		await store.receive(\.processLoaded) {
			$0.process = retried
		}
		await store.send(.backTapped) {
			$0.backStack = []
			$0.processId = 7
			$0.process = nil
		}
		await store.receive(\.processLoaded) {
			$0.process = finished
		}
		await store.skipInFlightEffects()
	}

	@Test("an answer for a run no longer on the page is dropped")
	func staleAnswerDropped() async {
		let store = TestStore(initialState: state()) {
			HomerProcessDetailReducer()
		}

		await store.send(.processLoaded(processId: 6, .success(HomerProcess(id: 6, status: .finished, agentName: "old"))))
	}

	@Test("kill asks first, and is offered only to who may kill")
	func killConfirms() async {
		let running = HomerProcess(id: 7, status: .working, agentName: "factory", owner: "cron")
		let killed = LockIsolated<[Int]>([])
		let store = TestStore(initialState: state(running)) {
			HomerProcessDetailReducer()
		} withDependencies: {
			$0.continuousClock = ImmediateClock()
			$0[HomerClient.self].killProcess = { _, id in killed.withValue { $0.append(id) } }
			$0[HomerProcessDetailClient.self].process = { _, _ in running }
		}
		store.exhaustivity = .off

		await store.send(.killTapped)
		#expect(store.state.alert != nil)
		await store.send(.alert(.presented(.killConfirmed))) {
			$0.actionInFlight = .kill
		}
		await store.receive(\.actionFinished)
		#expect(killed.value == [7])

		let viewer = HomerUser(username: "viewer", grants: [.init(agents: ["*"], actions: ["read"])])
		#expect(!state(running, user: viewer).canKill)
	}

	@Test("a 401 asks the instance to sign out")
	func unauthorized() async {
		let store = TestStore(initialState: state()) {
			HomerProcessDetailReducer()
		}

		await store.send(.processLoaded(processId: 7, .failure(HomerAPIError.unauthorized)))
		await store.receive(\.delegate, .unauthorized)
	}

	@Test("a change in the run's open questions tells the instance")
	func questionsChanged() async {
		var process = HomerProcess(id: 7, status: .working, agentName: "factory", openQuestions: 0)
		let store = TestStore(initialState: state(process)) {
			HomerProcessDetailReducer()
		}

		process.openQuestions = 1
		await store.send(.processLoaded(processId: 7, .success(process))) {
			$0.process = process
		}
		await store.receive(\.delegate, .questionsChanged)
	}

	@Test("the running command's output opens on its live files")
	func liveOutput() async {
		let running = HomerProcess(
			id: 7,
			status: .working,
			agentName: "factory",
			executions: [.init(label: "checkout", resultCode: 0)],
			currentCommand: "develop",
			currentCommandStart: 1_700_000_000
		)
		let store = TestStore(initialState: state(running)) {
			HomerProcessDetailReducer()
		}

		await store.send(.viewOutputTapped(executionIndex: 1, stream: .stdout)) {
			$0.output = HomerProcessOutputReducer.State(
				baseURL: Self.baseURL,
				processId: 7,
				executionIndex: 1,
				paths: [.stdout: "cmd_1.out", .stderr: "cmd_1.err"],
				stream: .stdout,
				isLiveCommand: true,
				commandStart: 1_700_000_000
			)
		}
	}
}

@MainActor
@Suite("Homer command output", .dependencies)
struct HomerProcessOutputReducerTests {
	private static let baseURL = "https://homer.example.com"

	private func state(isLive: Bool = false) -> HomerProcessOutputReducer.State {
		HomerProcessOutputReducer.State(
			baseURL: Self.baseURL,
			processId: 7,
			executionIndex: 1,
			paths: [.stdout: "cmd_1.out", .stderr: "cmd_1.err"],
			stream: .stdout,
			isLiveCommand: isLive
		)
	}

	@Test("a finished file is read once")
	func completeFile() async {
		let store = TestStore(initialState: state()) {
			HomerProcessOutputReducer()
		} withDependencies: {
			$0[HomerProcessDetailClient.self].artifactContent = { _, processId, path in
				#expect(processId == 7)
				#expect(path == "cmd_1.out")
				return HomerArtifactContent(text: "done\n", byteCount: 5, isComplete: true)
			}
		}

		await store.send(.task) {
			$0.outputs[.stdout] = .init()
			$0.outputs[.stdout]?.isLoading = true
		}
		await store.receive(\.loaded) {
			var output = HomerProcessOutputReducer.Output()
			output.text = "done\n"
			output.byteCount = 5
			output.hasLoaded = true
			output.transcript = HomerClaudeTranscript(parsing: "done\n")
			$0.outputs[.stdout] = output
		}
		#expect(store.state.effectiveMode == .raw)
	}

	@Test("a file still being written is tailed from where the read ended")
	func tailsFromReadEnd() async {
		let offsets = LockIsolated<[Int]>([])
		let store = TestStore(initialState: state(isLive: true)) {
			HomerProcessOutputReducer()
		} withDependencies: {
			$0[HomerProcessDetailClient.self].artifactContent = { _, _, _ in
				HomerArtifactContent(text: "one\n", byteCount: 4, isComplete: false)
			}
			$0[HomerProcessDetailClient.self].logEvents = { _, _, index, stream, offset in
				#expect(index == 1)
				#expect(stream == .stdout)
				offsets.withValue { $0.append(offset) }
				return AsyncThrowingStream { continuation in
					continuation.yield(.chunk(text: "two\n", endOffset: 8))
					continuation.yield(.end)
					continuation.finish()
				}
			}
		}
		store.exhaustivity = .off(showSkippedAssertions: false)

		await store.send(.task)
		await store.receive(\.loaded)
		#expect(store.state.output.isTailing)
		await store.receive(\.logEvent)
		await store.receive(\.logEvent)

		#expect(offsets.value == [4])
		#expect(store.state.output.text == "one\ntwo\n")
		#expect(store.state.output.isComplete)
		#expect(!store.state.output.isTailing)
	}

	@Test("bytes the tail already delivered are not added twice")
	func duplicateChunkDropped() async {
		var initialState = state()
		var output = HomerProcessOutputReducer.Output()
		output.text = "one\n"
		output.byteCount = 4
		output.isComplete = false
		output.hasLoaded = true
		initialState.outputs[.stdout] = output
		let store = TestStore(initialState: initialState) {
			HomerProcessOutputReducer()
		}

		await store.send(.logEvent(.stdout, .chunk(text: "one\n", endOffset: 4)))
	}

	@Test("a running command's file that does not exist yet is waited for")
	func liveFileNotYetWritten() async {
		let store = TestStore(initialState: state(isLive: true)) {
			HomerProcessOutputReducer()
		} withDependencies: {
			$0[HomerProcessDetailClient.self].artifactContent = { _, _, _ in
				throw HomerAPIError.server(status: 404, message: "Artifact file not found: cmd_1.out")
			}
			$0[HomerProcessDetailClient.self].logEvents = { _, _, _, _, offset in
				#expect(offset == 0)
				return AsyncThrowingStream { $0.yield(.end); $0.finish() }
			}
		}
		store.exhaustivity = .off(showSkippedAssertions: false)

		await store.send(.task)
		await store.receive(\.loaded)
		await store.receive(\.logEvent)
		#expect(store.state.output.hasLoaded)
		#expect(store.state.output.error == nil)
		#expect(store.state.output.isComplete)
	}

	@Test("switching streams loads the other one and lets it pick its own view")
	func switchStream() async {
		var initialState = state()
		initialState.mode = .raw
		let store = TestStore(initialState: initialState) {
			HomerProcessOutputReducer()
		} withDependencies: {
			$0[HomerProcessDetailClient.self].artifactContent = { _, _, path in
				#expect(path == "cmd_1.err")
				return HomerArtifactContent(text: "", byteCount: 0, isComplete: true)
			}
		}
		store.exhaustivity = .off(showSkippedAssertions: false)

		await store.send(.binding(.set(\.stream, .stderr))) {
			$0.stream = .stderr
			$0.mode = nil
		}
		await store.receive(\.loaded)
		#expect(store.state.output.hasLoaded)
	}
}
