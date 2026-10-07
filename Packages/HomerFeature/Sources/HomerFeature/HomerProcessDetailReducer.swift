import ComposableArchitecture
import Foundation

/// A process's page (`app/(dashboard)/processes/[id]/page.tsx`), natively: its status and
/// actions, runner, open questions, status timeline and executions — each with its output, and
/// the LangGraph workflow's state for the command that runs one. Kept current by polling, as the
/// list is. A retry, a resume or a sub run's link opens the other run here, and Back returns.
@Reducer
public struct HomerProcessDetailReducer: Sendable {
	/// The list's cadence: the poll stands in for the console's status stream.
	static let pollInterval: Duration = .seconds(5)
	/// The console's `refetchInterval` for the open workflow.
	static let workflowPollInterval: Duration = .seconds(5)

	/// Whether the run has a LangGraph workflow, from the cheap probe.
	public enum LangGraphProbe: Equatable, Sendable {
		case unknown
		case probing
		/// No workflow when asked. The workflow's artifact is written before its graph starts,
		/// so a run asked before its LangGraph command began is asked again once a command runs
		/// that the answer did not see.
		case none(currentCommand: String?)
		/// The label of the command that runs the workflow.
		case found(label: String)
	}

	@ObservableState
	public struct State: Equatable {
		public let baseURL: String
		public let user: HomerUser
		public internal(set) var processId: Int
		/// The runs this page showed before, most recent last — Back returns to them.
		public internal(set) var backStack: [Int] = []
		public internal(set) var process: HomerProcess?
		/// The last refresh's failure; the last good process stays on screen under it.
		public internal(set) var loadError: String?

		public internal(set) var expandedExecutions: Set<Int> = []
		/// The running command's workflow, shown under it.
		public internal(set) var isLiveWorkflowExpanded = false
		public internal(set) var langGraphProbe: LangGraphProbe = .unknown
		/// The workflow's node states, polled while it is shown.
		public internal(set) var workflow: HomerLangGraphStatus?
		var isPollingWorkflow = false

		/// Kill, retry or resume still waiting on the server.
		public internal(set) var actionInFlight: Action.ProcessAction?
		/// Artifacts of the executions' rows being saved.
		public internal(set) var downloadingPaths: Set<String> = []

		/// A command's output, over the page.
		@Presents
		public var output: HomerProcessOutputReducer.State?
		@Presents
		public var artifacts: HomerArtifactsReducer.State?
		@Presents
		public var alert: AlertState<Action.Alert>?
		/// The run in the web console, for its workflow graph — a sheet over this one.
		public var webPage: HomerWebPage?

		public init(baseURL: String, processId: Int, user: HomerUser) {
			self.baseURL = baseURL
			self.processId = processId
			self.user = user
		}

		public var langGraphLabel: String? {
			if case let .found(label) = langGraphProbe {
				return label
			}
			return workflow?.label
		}

		/// The running command is the workflow, so it can show the graph's state live.
		public var liveCommandIsWorkflow: Bool {
			guard let current = process?.currentCommand else {
				return false
			}
			return current == langGraphLabel
		}

		public var canKill: Bool {
			process.map { $0.isKillable && user.canKill($0) } ?? false
		}

		public var canRetry: Bool {
			process.map { $0.isRetryable && user.canRetry($0) } ?? false
		}

		/// Only a run that ended badly and has a workflow checkpoint to start again from.
		public var canResume: Bool {
			guard let process, process.isResumeEligible, case .found = langGraphProbe else {
				return false
			}
			return user.canRetry(process)
		}

		/// Whether the workflow's node states are on screen: under the expanded execution that
		/// ran it, or under the running command.
		var showsWorkflow: Bool {
			guard let label = langGraphLabel, let process else {
				return false
			}
			let expandedRunsIt = expandedExecutions.contains { index in
				process.executions.indices.contains(index) && process.executions[index].label == label
			}
			return expandedRunsIt || (isLiveWorkflowExpanded && liveCommandIsWorkflow)
		}

		/// The probe is asked only when its answer is used: by Resume, by an expanded
		/// execution, or by the running command's workflow toggle.
		var needsProbe: Bool {
			guard let process,
			      process.isResumeEligible || !expandedExecutions.isEmpty || process.currentCommand != nil
			else {
				return false
			}
			switch langGraphProbe {
			case .unknown:
				return true
			case let .none(currentCommand):
				return process.currentCommand != nil && process.currentCommand != currentCommand
			case .probing, .found:
				return false
			}
		}
	}

	public enum Action: BindableAction {
		case binding(BindingAction<State>)
		/// The page came on screen; it polls until it is dismissed.
		case task
		case refreshTapped
		case processLoaded(processId: Int, Result<HomerProcess, any Error>)
		case langGraphProbed(processId: Int, currentCommand: String?, Result<HomerLangGraphStatus?, any Error>)
		case workflowLoaded(processId: Int, Result<HomerLangGraphStatus?, any Error>)

		case executionToggled(index: Int)
		case liveWorkflowToggled
		case viewOutputTapped(executionIndex: Int, stream: HomerOutputStream)
		case downloadTapped(path: String)
		case downloadFinished(path: String, Result<URL, any Error>)
		case browseArtifactsTapped

		case killTapped
		case retryTapped
		case resumeTapped
		case actionFinished(processId: Int, ProcessAction, Result<Int?, any Error>)
		/// Another run: a sub run of the workflow, or the run a retry or resume started.
		case processLinkTapped(processId: Int)
		case backTapped
		case openInWebConsoleTapped

		case output(PresentationAction<HomerProcessOutputReducer.Action>)
		case artifacts(PresentationAction<HomerArtifactsReducer.Action>)
		case alert(PresentationAction<Alert>)
		case delegate(Delegate)

		public enum Alert: Equatable, Sendable {
			case killConfirmed
		}

		public enum ProcessAction: Equatable, Sendable {
			case kill
			case retry
			case resume
		}

		public enum Delegate: Equatable, Sendable {
			/// A call answered 401: the instance's session expired.
			case unauthorized
			/// The run's open-question count moved: the instance's questions are stale.
			case questionsChanged
		}
	}

	private nonisolated enum CancelID: Hashable {
		case processPolling
		case probe
		case workflowPolling
	}

	@Dependency(HomerProcessDetailClient.self)
	private var client

	@Dependency(HomerClient.self)
	private var homerClient

	@Dependency(\.continuousClock)
	private var clock

	public init() {}

	public var body: some Reducer<State, Action> {
		BindingReducer()
		Reduce(core)
			.ifLet(\.$output, action: \.output) {
				HomerProcessOutputReducer()
			}
			.ifLet(\.$artifacts, action: \.artifacts) {
				HomerArtifactsReducer()
			}
			.ifLet(\.$alert, action: \.alert)
	}

	private func core(_ state: inout State, _ action: Action) -> Effect<Action> {
		switch action {
		case .binding:
			return .none

		case .task, .refreshTapped:
			return poll(state)

		case let .processLoaded(processId, .success(process)):
			guard processId == state.processId else {
				return .none
			}
			let questionsChanged = state.process.map { ($0.openQuestions ?? 0) != (process.openQuestions ?? 0) } ?? false
			state.process = process
			state.loadError = nil
			return .merge(
				syncWorkflow(&state),
				questionsChanged ? .send(.delegate(.questionsChanged)) : .none
			)

		case let .processLoaded(processId, .failure(error)):
			guard processId == state.processId else {
				return .none
			}
			if error as? HomerAPIError == .unauthorized {
				return .send(.delegate(.unauthorized))
			}
			state.loadError = error.localizedDescription
			return .none

		case let .langGraphProbed(processId, currentCommand, result):
			guard processId == state.processId else {
				return .none
			}
			switch result {
			case let .success(status?):
				state.langGraphProbe = .found(label: status.label)
			case .success(nil):
				state.langGraphProbe = .none(currentCommand: currentCommand)
			case let .failure(error):
				if error as? HomerAPIError == .unauthorized {
					return .send(.delegate(.unauthorized))
				}
				// Taken as no workflow: Resume and the graph stay hidden, as in the console.
				state.langGraphProbe = .none(currentCommand: currentCommand)
			}
			return syncWorkflow(&state)

		case let .workflowLoaded(processId, result):
			guard processId == state.processId, state.isPollingWorkflow else {
				return .none
			}
			switch result {
			case let .success(status):
				state.workflow = status
			case let .failure(error):
				if error as? HomerAPIError == .unauthorized {
					return .send(.delegate(.unauthorized))
				}
				// The workflow's own errors arrive in `error` with a 200; a failed request
				// keeps the last status on screen.
			}
			return .none

		case let .executionToggled(index):
			if state.expandedExecutions.remove(index) == nil {
				state.expandedExecutions.insert(index)
			}
			return syncWorkflow(&state)

		case .liveWorkflowToggled:
			state.isLiveWorkflowExpanded.toggle()
			return syncWorkflow(&state)

		case let .viewOutputTapped(executionIndex, stream):
			guard let process = state.process else {
				return .none
			}
			let paths: [HomerOutputStream: String]
			let isLive: Bool
			if process.executions.indices.contains(executionIndex) {
				let execution = process.executions[executionIndex]
				paths = [.stdout: execution.stdOut, .stderr: execution.stdErr].compactMapValues { $0 }
				isLive = false
			}
			else {
				// The running command's files, which no execution names yet.
				paths = Dictionary(uniqueKeysWithValues: HomerOutputStream.allCases.map {
					($0, HomerArtifactPath.liveOutput(executionIndex: executionIndex, stream: $0))
				})
				isLive = true
			}
			state.output = HomerProcessOutputReducer.State(
				baseURL: state.baseURL,
				processId: state.processId,
				executionIndex: executionIndex,
				paths: paths,
				stream: stream,
				isLiveCommand: isLive,
				commandStart: isLive ? process.currentCommandStart : nil
			)
			return .none

		case let .downloadTapped(path):
			guard state.downloadingPaths.insert(path).inserted else {
				return .none
			}
			return .run { [baseURL = state.baseURL, processId = state.processId] send in
				await send(.downloadFinished(path: path, Result {
					try await client.downloadArtifact(baseURL, processId, path)
				}))
			}

		case let .downloadFinished(path, result):
			state.downloadingPaths.remove(path)
			if case let .failure(error) = result {
				if error as? HomerAPIError == .unauthorized {
					return .send(.delegate(.unauthorized))
				}
				state.alert = Self.failureAlert(
					title: "Could Not Download \(HomerArtifactPath.fileName(path))",
					error: error
				)
			}
			return .none

		case .browseArtifactsTapped:
			state.artifacts = HomerArtifactsReducer.State(baseURL: state.baseURL, processId: state.processId)
			return .none

		case .killTapped:
			guard state.canKill else {
				return .none
			}
			state.alert = AlertState {
				TextState("Kill process #\(state.processId)?")
			} actions: {
				ButtonState(role: .destructive, action: .killConfirmed) {
					TextState("Kill Process")
				}
				ButtonState(role: .cancel) {
					TextState("Cancel")
				}
			} message: {
				TextState("This cannot be undone.")
			}
			return .none

		case .alert(.presented(.killConfirmed)):
			return perform(.kill, &state)

		case .retryTapped:
			guard state.canRetry else {
				return .none
			}
			return perform(.retry, &state)

		case .resumeTapped:
			guard state.canResume else {
				return .none
			}
			return perform(.resume, &state)

		case let .actionFinished(processId, action, result):
			guard processId == state.processId, state.actionInFlight == action else {
				return .none
			}
			state.actionInFlight = nil
			switch result {
			case let .success(newProcessId?):
				// The console takes you to the new run.
				return .send(.processLinkTapped(processId: newProcessId))
			case .success(nil):
				return poll(state)
			case let .failure(error):
				if error as? HomerAPIError == .unauthorized {
					return .send(.delegate(.unauthorized))
				}
				let verb = switch action {
				case .kill: "Kill"
				case .retry: "Retry"
				case .resume: "Resume"
				}
				state.alert = Self.failureAlert(title: "Could Not \(verb) #\(processId)", error: error)
				return .none
			}

		case let .processLinkTapped(processId):
			guard processId != state.processId else {
				return .none
			}
			state.backStack.append(state.processId)
			return show(processId, &state)

		case .backTapped:
			guard let previous = state.backStack.popLast() else {
				return .none
			}
			return show(previous, &state)

		case .openInWebConsoleTapped:
			state.webPage = HomerWebPage(
				baseURL: state.baseURL,
				path: "processes/\(state.processId)",
				title: "Process #\(state.processId)",
				cookies: homerClient.sessionCookies(state.baseURL)
			)
			return .none

		case .output(.presented(.delegate(.unauthorized))),
		     .artifacts(.presented(.delegate(.unauthorized))):
			state.output = nil
			state.artifacts = nil
			return .send(.delegate(.unauthorized))

		case .output, .artifacts, .alert, .delegate:
			return .none
		}
	}

	private static func failureAlert(title: String, error: any Error) -> AlertState<Action.Alert> {
		AlertState {
			TextState(title)
		} actions: {
			ButtonState(role: .cancel) {
				TextState("OK")
			}
		} message: {
			TextState(error.localizedDescription)
		}
	}

	private func perform(_ action: Action.ProcessAction, _ state: inout State) -> Effect<Action> {
		guard state.actionInFlight == nil else {
			return .none
		}
		state.actionInFlight = action
		return .run { [baseURL = state.baseURL, processId = state.processId] send in
			await send(.actionFinished(processId: processId, action, Result {
				switch action {
				case .kill:
					try await homerClient.killProcess(baseURL, processId)
					return nil
				case .retry:
					return try await homerClient.retryProcess(baseURL, processId)
				case .resume:
					return try await client.resumeProcess(baseURL, processId)
				}
			}))
		}
	}

	/// Puts another run on the page, from scratch.
	private func show(_ processId: Int, _ state: inout State) -> Effect<Action> {
		state.processId = processId
		state.process = nil
		state.loadError = nil
		state.expandedExecutions = []
		state.isLiveWorkflowExpanded = false
		state.langGraphProbe = .unknown
		state.workflow = nil
		state.isPollingWorkflow = false
		state.actionInFlight = nil
		state.downloadingPaths = []
		state.output = nil
		state.artifacts = nil
		state.alert = nil
		state.webPage = nil
		return .merge(
			.cancel(id: CancelID.probe),
			.cancel(id: CancelID.workflowPolling),
			poll(state)
		)
	}

	/// Fetches the run right away, then every `pollInterval`. Restarting it replaces the loop.
	private func poll(_ state: State) -> Effect<Action> {
		.run { [baseURL = state.baseURL, processId = state.processId] send in
			while true {
				await send(.processLoaded(processId: processId, Result { try await client.process(baseURL, processId) }))
				try await clock.sleep(for: Self.pollInterval)
			}
		}
		.cancellable(id: CancelID.processPolling, cancelInFlight: true)
	}

	/// Asks the probe when its answer is needed, and polls the workflow's node states exactly
	/// while they are on screen.
	private func syncWorkflow(_ state: inout State) -> Effect<Action> {
		var effects: [Effect<Action>] = []
		if state.needsProbe {
			let currentCommand = state.process?.currentCommand
			state.langGraphProbe = .probing
			effects.append(
				.run { [baseURL = state.baseURL, processId = state.processId] send in
					await send(.langGraphProbed(
						processId: processId,
						currentCommand: currentCommand,
						Result { try await client.langGraphStatus(baseURL, processId, false) }
					))
				}
				.cancellable(id: CancelID.probe, cancelInFlight: true)
			)
		}
		if state.showsWorkflow != state.isPollingWorkflow {
			state.isPollingWorkflow = state.showsWorkflow
			if state.isPollingWorkflow {
				// Polled whatever the run's status: a parked segment is FINISHED while its thread
				// moves on in later runs, so the node states still change.
				effects.append(
					.run { [baseURL = state.baseURL, processId = state.processId] send in
						while true {
							await send(.workflowLoaded(processId: processId, Result {
								try await client.langGraphStatus(baseURL, processId, true)
							}))
							try await clock.sleep(for: Self.workflowPollInterval)
						}
					}
					.cancellable(id: CancelID.workflowPolling, cancelInFlight: true)
				)
			}
			else {
				effects.append(.cancel(id: CancelID.workflowPolling))
			}
		}
		return .merge(effects)
	}
}
