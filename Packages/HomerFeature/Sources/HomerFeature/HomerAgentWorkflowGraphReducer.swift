import ComposableArchitecture
import Foundation

/// An agent's workflow graphs (the console's `workflow-graph-card.tsx` on the agent's page): the
/// structure of each of its LangGraph commands, as a sheet over the Agents page. Read once when
/// the sheet opens and again on Refresh, never polled: the server inspects the agent's Python
/// modules in a subprocess on every call.
@Reducer
public struct HomerAgentWorkflowGraphReducer: Sendable {
	@ObservableState
	public struct State: Equatable {
		public let baseURL: String
		public let agentName: String
		/// Nil until the first answer.
		public internal(set) var graphs: [HomerAgentWorkflowGraph]?
		public internal(set) var loadError: String?
		public internal(set) var isLoading = false

		public init(baseURL: String, agentName: String) {
			self.baseURL = baseURL
			self.agentName = agentName
		}
	}

	public enum Action {
		/// The sheet came on screen.
		case task
		case refreshTapped
		case graphsLoaded(Result<[HomerAgentWorkflowGraph], any Error>)
		case closeTapped
		case delegate(Delegate)

		public enum Delegate: Equatable {
			case unauthorized
		}
	}

	/// A load in flight. The agent's page holds this reducer as plain state, so it stops the
	/// load itself when it goes (`HomerAgentDetailReducer.cancelEffects`).
	nonisolated enum CancelID: Hashable {
		case load
	}

	@Dependency(HomerAgentsClient.self)
	private var agentsClient

	@Dependency(\.dismiss)
	private var dismiss

	public init() {}

	public var body: some Reducer<State, Action> {
		Reduce { state, action in
			switch action {
			case .task, .refreshTapped:
				guard !state.isLoading else {
					return .none
				}
				state.isLoading = true
				return .run { [baseURL = state.baseURL, agentName = state.agentName] send in
					await send(.graphsLoaded(Result { try await agentsClient.workflowGraphs(baseURL, agentName) }))
				}
				.cancellable(id: CancelID.load)

			case let .graphsLoaded(.success(graphs)):
				state.isLoading = false
				state.graphs = graphs
				state.loadError = nil
				return .none

			case let .graphsLoaded(.failure(error)):
				state.isLoading = false
				if error as? HomerAPIError == .unauthorized {
					return .send(.delegate(.unauthorized))
				}
				state.loadError = Self.loadErrorMessage(error, agentName: state.agentName)
				return .none

			case .closeTapped:
				return .run { _ in await dismiss() }

			case .delegate:
				return .none
			}
		}
	}

	/// The server hides an agent the user holds no grant on behind the 404 of an unknown one.
	static func loadErrorMessage(_ error: any Error, agentName: String) -> String {
		if case .server(status: 404, _) = error as? HomerAPIError {
			return "\(agentName) is no longer loaded."
		}
		return error.localizedDescription
	}
}
