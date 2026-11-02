import ComposableArchitecture
import Foundation

@Reducer
struct DeleteWorktreeConfirmationReducer {
	@ObservableState
	struct State: Equatable {
		let name: String
		/// Whether removing it also deletes its Xcode DerivedData (Settings), so the text can say so.
		let deletesDerivedData: Bool
		var forceRemoval: Bool = false
		var deleteLocalBranch: Bool = true
	}

	enum Action: BindableAction {
		case binding(BindingAction<State>)
		case cancelTapped
		case confirmTapped(forceRemoval: Bool, deleteLocalBranch: Bool)
	}

	var body: some Reducer<State, Action> {
		BindingReducer()
		Reduce { _, action in
			switch action {
			case .binding,
			     .cancelTapped,
			     .confirmTapped:
				.none
			}
		}
	}
}
