import ComposableArchitecture
import Foundation

/// The Agents and Schedules pages of one instance: both show the instance's agents, Schedules
/// only those with a cron. Agents mirrors the console's `agents/page.tsx` (search, Reload, the
/// agent cards, Run); Schedules its `schedules/page.tsx`. An agent's detail page, workflow
/// graph, file editor, debug runs and "New agent" open in the web console.
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
		/// The run the Run sheet started, opened once the sheet is gone — the web page is a sheet
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
		/// The console's file editor, which also holds the debug runs.
		case editTapped(agentName: String)
		/// The console's agents page, whose "New agent" dialog creates one.
		case newAgentTapped
		case processTapped(processId: Int)

		case delegate(HomerPageDelegate)
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

			case let .editTapped(agentName):
				let path = HomerAgent(name: agentName).consolePath + "/edit"
				return .send(.delegate(.openWebConsole(path: path, title: "Edit \(agentName)")))

			case .newAgentTapped:
				return .send(.delegate(.openWebConsole(path: "agents", title: "Agents")))

			case let .processTapped(processId):
				return .send(.delegate(.openWebConsole(path: "processes/\(processId)", title: "Process #\(processId)")))

			case .delegate:
				return .none
			}
		}
		.ifLet(\.$runAgent, action: \.runAgent) {
			HomerRunAgentReducer()
		}
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
