import ComposableArchitecture
import Foundation

/// The Agents and Schedules pages of one instance: both show the instance's agents, Schedules
/// only those with a cron. Agents mirrors the console's `agents/page.tsx` (search, Reload, the
/// agent cards, Run); Schedules its `schedules/page.tsx` (with its Run, which fires the cron
/// now). An agent's workflow graph is a sheet here; its detail page, file editor, debug runs
/// and "New agent" open in the web console.
@Reducer
public struct HomerAgentsReducer: Sendable {
	/// The console reads the list once and keeps it 5 minutes (`polling.agentsCacheTime`), then
	/// refetches when the server announces a reload on its `/stream/agents` events. A poll
	/// stands in for that stream here, as the process list's does for the status stream; it
	/// also keeps the schedules' next and last runs current once a cron has fired.
	static let pollInterval: Duration = .seconds(30)

	@ObservableState
	public struct State: Equatable {
		public let baseURL: String
		/// By name, as the console sorts them.
		public internal(set) var agents: IdentifiedArrayOf<HomerAgent> = []
		public internal(set) var hasLoaded = false
		/// The last refresh's failure; the last good list stays on screen below it.
		public internal(set) var loadError: String?
		/// The console's search: agents whose name contains it, ignoring case.
		public var searchText = ""
		public internal(set) var isReloading = false
		public internal(set) var reloadResult: HomerAgentReloadResult?
		public internal(set) var reloadError: String?
		@Presents
		public var runAgent: HomerRunAgentReducer.State?
		@Presents
		public var workflowGraph: HomerAgentWorkflowGraphReducer.State?
		/// Schedules whose "Run Now" is still waiting on the server.
		public internal(set) var cronRunsInFlight: Set<HomerAgent.ID> = []
		/// "Run Now"'s confirmation, and why a fire failed.
		@Presents
		public var alert: AlertState<Action.Alert>?
		/// The run the Run sheet started, opened once the sheet is gone — the run's page is a sheet
		/// too, and one sheet cannot come up while the other is still going.
		var processToOpen: Int?
		/// Between `shown` and `hidden`: the page polls.
		var isShown = false

		public init(baseURL: String) {
			self.baseURL = baseURL
		}

		/// The Agents page's cards.
		public var filteredAgents: [HomerAgent] {
			let search = searchText.lowercased()
			guard !search.isEmpty else {
				return Array(agents)
			}
			return agents.filter { $0.name.lowercased().contains(search) }
		}

		/// The Schedules page's rows.
		public var schedules: [HomerAgent] {
			HomerAgent.schedules(agents)
		}
	}

	public enum Action: BindableAction {
		case binding(BindingAction<State>)
		/// The page came on screen; it polls until `hidden`.
		case shown
		case hidden
		/// The header's Refresh: fetches right away, without waiting for the next poll.
		case refreshTapped
		case agentsLoaded(Result<[HomerAgent], any Error>)

		case reloadTapped
		case reloadFinished(Result<HomerAgentReloadResult, any Error>)
		case reloadResultDismissed
		case reloadErrorDismissed

		case runTapped(agentName: String)
		case runAgent(PresentationAction<HomerRunAgentReducer.Action>)
		/// The Run sheet went off screen, however it was closed.
		case runSheetDismissed

		/// The agent's console page: its parameters, workflow graph and run history.
		case agentTapped(agentName: String)
		case workflowGraphTapped(agentName: String)
		case workflowGraph(PresentationAction<HomerAgentWorkflowGraphReducer.Action>)
		/// The console's file editor, which also holds the debug runs.
		case editTapped(agentName: String)
		/// The console's agents page, whose "New agent" dialog creates one.
		case newAgentTapped
		case processTapped(processId: Int)

		/// The Schedules page's Run: fires the agent now as its cron would, once confirmed.
		case cronRunTapped(agentName: String)
		case cronRunFinished(agentName: String, Result<Void, any Error>)
		case alert(PresentationAction<Alert>)

		case delegate(HomerPageDelegate)

		public enum Alert: Equatable, Sendable {
			case cronRunConfirmed(agentName: String)
		}
	}

	private nonisolated enum CancelID: Hashable {
		case polling
	}

	@Dependency(HomerAgentsClient.self)
	private var agentsClient

	@Dependency(\.continuousClock)
	private var clock

	public init() {}

	public var body: some Reducer<State, Action> {
		BindingReducer()
		Reduce { state, action in
			switch action {
			case .binding:
				return .none

			case .shown:
				state.isShown = true
				return poll(state)

			case .refreshTapped:
				return state.isShown ? poll(state) : .none

			case .hidden:
				state.isShown = false
				return .cancel(id: CancelID.polling)

			case let .agentsLoaded(.success(agents)):
				let sorted = agents.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
				state.agents = IdentifiedArray(sorted, uniquingIDsWith: { first, _ in first })
				state.hasLoaded = true
				state.loadError = nil
				return .none

			case let .agentsLoaded(.failure(error)):
				if error as? HomerAPIError == .unauthorized {
					return .send(.delegate(.unauthorized))
				}
				state.loadError = error.localizedDescription
				return .none

			case .reloadTapped:
				guard !state.isReloading else {
					return .none
				}
				state.isReloading = true
				state.reloadResult = nil
				state.reloadError = nil
				return .run { [baseURL = state.baseURL] send in
					await send(.reloadFinished(Result { try await agentsClient.reload(baseURL) }))
				}

			case let .reloadFinished(result):
				// A reload of a user since signed out lands in a state that never started it.
				guard state.isReloading else {
					return .none
				}
				state.isReloading = false
				switch result {
				case let .success(reloadResult):
					state.reloadResult = reloadResult
					// The console refetches the list after a reload.
					return state.isShown ? poll(state) : .none
				case let .failure(error):
					if error as? HomerAPIError == .unauthorized {
						return .send(.delegate(.unauthorized))
					}
					state.reloadError = error.localizedDescription
					return .none
				}

			case .reloadResultDismissed:
				state.reloadResult = nil
				return .none

			case .reloadErrorDismissed:
				state.reloadError = nil
				return .none

			case let .runTapped(agentName):
				guard let agent = state.agents[id: agentName] else {
					return .none
				}
				state.processToOpen = nil
				state.runAgent = HomerRunAgentReducer.State(baseURL: state.baseURL, agent: agent)
				return .none

			case let .runAgent(.presented(.delegate(.started(processId)))):
				state.runAgent = nil
				state.processToOpen = processId
				return .none

			case .runAgent(.presented(.delegate(.unauthorized))):
				state.runAgent = nil
				return .send(.delegate(.unauthorized))

			case .runAgent:
				return .none

			case .runSheetDismissed:
				guard let processId = state.processToOpen else {
					return .none
				}
				state.processToOpen = nil
				// The console takes you to the new run.
				return .send(.processTapped(processId: processId))

			case let .agentTapped(agentName):
				let path = HomerAgent(name: agentName).consolePath
				return .send(.delegate(.openWebConsole(path: path, title: agentName)))

			case let .workflowGraphTapped(agentName):
				state.workflowGraph = HomerAgentWorkflowGraphReducer.State(baseURL: state.baseURL, agentName: agentName)
				return .none

			case .workflowGraph(.presented(.delegate(.unauthorized))):
				state.workflowGraph = nil
				return .send(.delegate(.unauthorized))

			case .workflowGraph:
				return .none

			case let .editTapped(agentName):
				let path = HomerAgent(name: agentName).consolePath + "/edit"
				return .send(.delegate(.openWebConsole(path: path, title: "Edit \(agentName)")))

			case .newAgentTapped:
				return .send(.delegate(.openWebConsole(path: "agents", title: "Agents")))

			case let .processTapped(processId):
				return .send(.delegate(.openProcess(processId: processId)))

			case let .cronRunTapped(agentName):
				guard !state.cronRunsInFlight.contains(agentName) else {
					return .none
				}
				// The console's own warning: nothing comes back to say the run did not start.
				state.alert = AlertState {
					TextState("Run \(agentName) now?")
				} actions: {
					ButtonState(action: .cronRunConfirmed(agentName: agentName)) {
						TextState("Run Now")
					}
					ButtonState(role: .cancel) {
						TextState("Cancel")
					}
				} message: {
					TextState(
						"This starts the agent immediately with its cron semantics — no parameters are asked for, and the run is owned by the scheduler. A fire that starts no run (cost cap, cooldown, lock, parallel-run or queued-runs cap) is only logged, never reported as an error."
					)
				}
				return .none

			case let .alert(.presented(.cronRunConfirmed(agentName))):
				guard state.cronRunsInFlight.insert(agentName).inserted else {
					return .none
				}
				return .run { [baseURL = state.baseURL] send in
					await send(.cronRunFinished(
						agentName: agentName,
						Result { try await agentsClient.fireCron(baseURL, agentName) }
					))
				}

			case .alert:
				return .none

			case let .cronRunFinished(agentName, result):
				// Not waited on any more: the page's state was replaced (signed out) meanwhile.
				guard state.cronRunsInFlight.remove(agentName) != nil else {
					return .none
				}
				switch result {
				case .success:
					// The fire records the run as the schedule's last one; the console refetches
					// the list to show it.
					return state.isShown ? poll(state) : .none
				case let .failure(error):
					if error as? HomerAPIError == .unauthorized {
						return .send(.delegate(.unauthorized))
					}
					state.alert = AlertState {
						TextState("Could not run \(agentName)")
					} actions: {
						ButtonState(role: .cancel) {
							TextState("OK")
						}
					} message: {
						TextState(Self.cronRunErrorMessage(error, agentName: agentName))
					}
					return .none
				}

			case .delegate:
				return .none
			}
		}
		.ifLet(\.$runAgent, action: \.runAgent) {
			HomerRunAgentReducer()
		}
		.ifLet(\.$workflowGraph, action: \.workflowGraph) {
			HomerAgentWorkflowGraphReducer()
		}
		.ifLet(\.$alert, action: \.alert)
	}

	/// The server answers a non-admin with the 404 of an unknown agent, so the two cannot be told
	/// apart.
	static func cronRunErrorMessage(_ error: any Error, agentName: String) -> String {
		if case .server(status: 404, _) = error as? HomerAPIError {
			return "\(agentName) is no longer loaded, or your account may not run schedules."
		}
		return error.localizedDescription
	}

	/// Fetches right away, then every `pollInterval`. Restarting it replaces the running loop.
	private func poll(_ state: State) -> Effect<Action> {
		.run { [baseURL = state.baseURL] send in
			while true {
				await send(.agentsLoaded(Result { try await agentsClient.agents(baseURL) }))
				try await clock.sleep(for: Self.pollInterval)
			}
		}
		.cancellable(id: CancelID.polling, cancelInFlight: true)
	}
}
