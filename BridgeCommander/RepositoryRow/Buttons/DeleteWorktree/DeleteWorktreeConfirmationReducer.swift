import ComposableArchitecture
import Foundation

@Reducer
struct DeleteWorktreeConfirmationReducer {
	@ObservableState
	struct State: Equatable {
		let name: String
		var forceRemoval: Bool = false
	}

	enum Action: BindableAction {
		case binding(BindingAction<State>)
		case cancelTapped
		case confirmTapped(forceRemoval: Bool)
	}

	var body: some Reducer<State, Action> {
		BindingReducer()
		Reduce { _, action in
			switch action {
			case .cancelTapped, .confirmTapped, .binding:
				.none
			}
		}
	}
}
