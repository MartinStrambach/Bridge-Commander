import ComposableArchitecture
import Foundation

/// The Continuations page of one instance.
@Reducer
public struct HomerContinuationsReducer: Sendable {
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
