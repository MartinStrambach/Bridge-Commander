import ComposableArchitecture
import Foundation

/// The Agents and Schedules pages of one instance: both show the instance's agents, Schedules
/// only those with a cron.
@Reducer
public struct HomerAgentsReducer: Sendable {
	@ObservableState
	public struct State: Equatable {
		public let baseURL: String

		public init(baseURL: String) {
			self.baseURL = baseURL
		}
	}

	public enum Action {
		/// The page came on screen; it polls until `hidden`.
		case shown
		case hidden
		case delegate(HomerPageDelegate)
	}

	public init() {}

	public var body: some Reducer<State, Action> {
		Reduce { _, action in
			switch action {
			case .shown, .hidden, .delegate:
				return .none
			}
		}
	}
}
