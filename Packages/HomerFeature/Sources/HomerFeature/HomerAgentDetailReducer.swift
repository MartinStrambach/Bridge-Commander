import ComposableArchitecture
import Foundation

/// An agent's page (the console's `agents/[name]/page.tsx`), shown in place of the Agents or
/// Schedules page that opened it: the agent with Edit and Run, its run history, its parameters
/// and its workflow graphs. The agent is the list's — the console's `useAgent` finds it in the
/// agents list too — and `HomerAgentsReducer` keeps it current as the list polls. The run
/// history is polled here while the page is on screen; the workflow graphs are read when their
/// section is first shown, as the server inspects the agent's modules on every call.
@Reducer
public struct HomerAgentDetailReducer: Sendable {
	/// The process list's page size and cadence.
	static let pageSize = HomerInstanceReducer.pageSize
	static let pollInterval = HomerInstanceReducer.processPollInterval

	/// The page's sections. The console stacks them; here each gets the whole page, so the run
	/// table and a large graph each scroll by themselves.
	public enum Section: Hashable, Sendable, CaseIterable {
		case runs
		case parameters
		case workflow
	}

	@ObservableState
	public struct State: Equatable {
		public let baseURL: String
		public let agentName: String
		/// The page it is shown in place of, and goes back to.
		public let openedFrom: HomerAgentsReducer.Page
		/// Nil once the agents list no longer has it (a reload removed it, or the grant went):
		/// the console's "Agent not found".
		public internal(set) var agent: HomerAgent?
		public var section: Section = .runs

		/// Newest first, as the console lists them.
		public internal(set) var runs: IdentifiedArrayOf<HomerProcess> = []
		public internal(set) var runTotal = 0
		/// Grows by a page on "Load More", like the process list's, so a refresh keeps every
		/// loaded row current.
		public internal(set) var runLimit = HomerAgentDetailReducer.pageSize
		public internal(set) var hasLoadedRuns = false
		/// The last refresh's failure; the last good rows stay on screen below it.
		public internal(set) var runsError: String?
		/// Runs whose Kill or Retry is still waiting on the server.
		public internal(set) var runActionsInFlight: Set<HomerProcess.ID> = []

		public var workflowGraph: HomerAgentWorkflowGraphReducer.State
		/// Kill's confirmation, and why a Kill or Retry failed.
		@Presents
		public var alert: AlertState<Action.Alert>?

		/// Between `shown` and the parent's hiding it: the run history polls. Set back by
		/// `HomerAgentsReducer`, which also stops the poll — the page may be gone by then.
		var isShown = false

		public init(
			baseURL: String,
			agentName: String,
			openedFrom: HomerAgentsReducer.Page = .agents,
			agent: HomerAgent? = nil
		) {
			self.baseURL = baseURL
			self.agentName = agentName
			self.openedFrom = openedFrom
			self.agent = agent
			workflowGraph = HomerAgentWorkflowGraphReducer.State(baseURL: baseURL, agentName: agentName)
		}

		public var canLoadMoreRuns: Bool {
			runs.count < runTotal
		}

		/// What the listed runs cost together, as the process list's "Total cost".
		public var listedCostUsd: Double {
			runs.reduce(0) { $0 + ($1.costUsd ?? 0) }
		}

		var runQuery: HomerProcessQuery {
			HomerProcessQuery(agentName: agentName, limit: runLimit)
		}
	}

	public enum Action {
		/// The page came on screen; the run history polls until the parent hides it.
		case shown
		/// The header's Refresh.
		case refreshTapped
		case runsLoaded(Result<HomerProcessPage, any Error>)
		case loadMoreRunsTapped
		case sectionSelected(Section)

		case backTapped
		case runTapped
		case editTapped
		case processTapped(processId: Int)
		case killTapped(processId: Int)
		case retryTapped(processId: Int)
		case runActionFinished(
			processId: Int,
			HomerInstanceReducer.Action.ProcessAction,
			Result<Int?, any Error>
		)
		case alert(PresentationAction<Alert>)
		case workflowGraph(HomerAgentWorkflowGraphReducer.Action)

		case delegate(Delegate)

		public enum Alert: Equatable, Sendable {
			case killConfirmed(processId: Int)
		}

		public enum Delegate: Equatable, Sendable {
			/// Back to the page that opened it.
			case back
			/// The Agents page's Run sheet.
			case run
			/// The console's file editor.
			case edit
			case openProcess(processId: Int)
			case unauthorized
		}
	}

	nonisolated enum CancelID: Hashable {
		case polling
		case runActions
	}

	/// Stops whatever the page still runs. The parent holds it as plain optional state, whose
	/// effects nothing cancels when it goes — and an instance that signs out replaces the
	/// parent's state outright — so the parent sends this when it drops the page.
	static func cancelEffects<A>() -> Effect<A> {
		.merge(
			.cancel(id: CancelID.polling),
			.cancel(id: CancelID.runActions),
			.cancel(id: HomerAgentWorkflowGraphReducer.CancelID.load)
		)
	}

	@Dependency(HomerClient.self)
	private var homerClient

	@Dependency(\.continuousClock)
	private var clock

	public init() {}

	public var body: some Reducer<State, Action> {
		Scope(\.workflowGraph, action: \.workflowGraph) {
			HomerAgentWorkflowGraphReducer()
		}
		Reduce { state, action in
			switch action {
			case .shown:
				state.isShown = true
				return poll(state)

			case .refreshTapped:
				guard state.isShown else {
					return .none
				}
				let graph: Effect<Action> = state.section == .workflow
					? .send(.workflowGraph(.refreshTapped))
					: .none
				return .merge(poll(state), graph)

			case let .runsLoaded(.success(page)):
				state.runs = IdentifiedArray(page.processes, uniquingIDsWith: { first, _ in first })
				state.runTotal = page.total
				state.hasLoadedRuns = true
				state.runsError = nil
				return .none

			case let .runsLoaded(.failure(error)):
				if error as? HomerAPIError == .unauthorized {
					return .send(.delegate(.unauthorized))
				}
				state.runsError = error.localizedDescription
				return .none

			case .loadMoreRunsTapped:
				guard state.canLoadMoreRuns else {
					return .none
				}
				state.runLimit += Self.pageSize
				return state.isShown ? poll(state) : .none

			case let .sectionSelected(section):
				state.section = section
				let graph = state.workflowGraph
				guard section == .workflow, graph.graphs == nil, graph.loadError == nil else {
					return .none
				}
				return .send(.workflowGraph(.task))

			case .backTapped:
				return .send(.delegate(.back))

			case .runTapped:
				return .send(.delegate(.run))

			case .editTapped:
				return .send(.delegate(.edit))

			case let .processTapped(processId):
				return .send(.delegate(.openProcess(processId: processId)))

			case let .killTapped(processId):
				state.alert = AlertState {
					TextState("Kill process #\(processId)?")
				} actions: {
					ButtonState(role: .destructive, action: .killConfirmed(processId: processId)) {
						TextState("Kill Process")
					}
					ButtonState(role: .cancel) {
						TextState("Cancel")
					}
				} message: {
					TextState("This cannot be undone.")
				}
				return .none

			case let .alert(.presented(.killConfirmed(processId))):
				guard state.runActionsInFlight.insert(processId).inserted else {
					return .none
				}
				return .run { [baseURL = state.baseURL] send in
					await send(.runActionFinished(processId: processId, .kill, Result {
						try await homerClient.killProcess(baseURL, processId)
						return nil
					}))
				}
				.cancellable(id: CancelID.runActions)

			case .alert:
				return .none

			case let .retryTapped(processId):
				guard state.runActionsInFlight.insert(processId).inserted else {
					return .none
				}
				return .run { [baseURL = state.baseURL] send in
					await send(.runActionFinished(processId: processId, .retry, Result {
						try await homerClient.retryProcess(baseURL, processId)
					}))
				}
				.cancellable(id: CancelID.runActions)

			case let .runActionFinished(processId, _, .success(newProcessId)):
				state.runActionsInFlight.remove(processId)
				let refresh = state.isShown ? poll(state) : .none
				guard let newProcessId else {
					return refresh
				}
				// The console takes you to the new run after a retry.
				return .merge(refresh, .send(.delegate(.openProcess(processId: newProcessId))))

			case let .runActionFinished(processId, action, .failure(error)):
				state.runActionsInFlight.remove(processId)
				if error as? HomerAPIError == .unauthorized {
					return .send(.delegate(.unauthorized))
				}
				state.alert = AlertState {
					TextState(action == .kill ? "Could Not Kill #\(processId)" : "Could Not Retry #\(processId)")
				} actions: {
					ButtonState(role: .cancel) {
						TextState("OK")
					}
				} message: {
					TextState(error.localizedDescription)
				}
				return .none

			case .workflowGraph(.delegate(.unauthorized)):
				return .send(.delegate(.unauthorized))

			case .workflowGraph:
				return .none

			case .delegate:
				return .none
			}
		}
		.ifLet(\.$alert, action: \.alert)
	}

	/// Fetches right away, then every `pollInterval`. Restarting it replaces the running loop, so
	/// an answer for a smaller page never lands after a larger one.
	private func poll(_ state: State) -> Effect<Action> {
		.run { [baseURL = state.baseURL, query = state.runQuery] send in
			while true {
				await send(.runsLoaded(Result { try await homerClient.processes(baseURL, query) }))
				try await clock.sleep(for: Self.pollInterval)
			}
		}
		.cancellable(id: CancelID.polling, cancelInFlight: true)
	}
}
