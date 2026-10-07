import ComposableArchitecture
import Foundation

/// The Run sheet of one agent (the console's `run-agent-dialog.tsx`): a field per input,
/// grouped by where the run reads it from, checked as typed and again on Run; or the same call
/// as a curl command.
@Reducer
public struct HomerRunAgentReducer: Sendable {
	@ObservableState
	public struct State: Equatable, Identifiable {
		public enum Mode: Equatable, Sendable {
			case configure
			case curl
		}

		public let baseURL: String
		public let agent: HomerAgent
		public var mode: Mode = .configure
		/// Every input's value, keyed by parameter name; empty to start with, as in the console.
		public internal(set) var values: [String: String]
		/// Shown under each field. A field is checked when it changes, and all of them on Run.
		public internal(set) var errors: [String: String] = [:]
		public internal(set) var isRunning = false
		public internal(set) var runError: String?

		public init(baseURL: String, agent: HomerAgent) {
			self.baseURL = baseURL
			self.agent = agent
			self.values = Dictionary(agent.inputs.map { ($0.paramName, "") }, uniquingKeysWith: { first, _ in first })
		}

		public var id: String {
			agent.name
		}

		/// The inputs shown and checked: those of a source the console knows.
		var inputs: [HomerAgent.Input] {
			agent.inputs.filter { $0.source != .unknown }
		}

		/// The console's `canRun`: no error shown and every required field filled.
		public var canRun: Bool {
			errors.isEmpty && inputs.allSatisfy { input in
				!input.required || !(values[input.paramName] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
			}
		}

		public var request: HomerAgentRunRequest {
			HomerAgentRunRequest(agent: agent, values: values)
		}

		public var curlCommand: String {
			request.curlCommand(baseURL: baseURL, agentName: agent.name)
		}
	}

	public enum Action: BindableAction {
		case binding(BindingAction<State>)
		case valueChanged(paramName: String, value: String)
		case runTapped
		case runFinished(Result<Int, any Error>)
		case cancelTapped
		case delegate(Delegate)

		@CasePathable
		public enum Delegate: Equatable, Sendable {
			/// The run started; the sheet's owner closes it and opens the run.
			case started(processId: Int)
			/// The session expired.
			case unauthorized
		}
	}

	private nonisolated enum CancelID: Hashable {
		case run
	}

	@Dependency(HomerAgentsClient.self)
	private var agentsClient

	@Dependency(\.dismiss)
	private var dismiss

	public init() {}

	public var body: some Reducer<State, Action> {
		BindingReducer()
		Reduce { state, action in
			switch action {
			case .binding:
				return .none

			case let .valueChanged(paramName, value):
				state.values[paramName] = value
				guard let input = state.inputs.first(where: { $0.paramName == paramName }) else {
					return .none
				}
				state.errors[paramName] = HomerAgentInputValidation.error(for: input, value: value)
				return .none

			case .runTapped:
				guard !state.isRunning else {
					return .none
				}
				state.errors = HomerAgentInputValidation.errors(for: state.inputs, values: state.values)
				guard state.errors.isEmpty else {
					return .none
				}
				state.isRunning = true
				state.runError = nil
				return .run { [baseURL = state.baseURL, name = state.agent.name, request = state.request] send in
					await send(.runFinished(Result { try await agentsClient.run(baseURL, name, request) }))
				}
				.cancellable(id: CancelID.run, cancelInFlight: true)

			case let .runFinished(.success(processId)):
				state.isRunning = false
				return .send(.delegate(.started(processId: processId)))

			case let .runFinished(.failure(error)):
				state.isRunning = false
				if error as? HomerAPIError == .unauthorized {
					return .send(.delegate(.unauthorized))
				}
				state.runError = error.localizedDescription
				return .none

			case .cancelTapped:
				return .run { _ in
					await dismiss()
				}

			case .delegate:
				return .none
			}
		}
	}
}
