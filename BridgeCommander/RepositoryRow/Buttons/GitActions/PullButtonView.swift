import ComposableArchitecture
import SwiftUI

// MARK: - Pull Button View

struct PullButtonView: View {
	let store: StoreOf<PullButtonReducer>

	var body: some View {
		Group {
			if store.isPulling {
				GitOperationProgressView(
					text: "Pulling...",
					color: .blue,
					helpText: "Pulling changes from remote..."
				)
			}
			else {
				Button {
					store.send(.pullTapped)
				} label: {
					Label("Pull", systemImage: "arrow.down.circle")
				}
			}
		}
		.alert(store: store.scope(state: \.$alert, action: \.alert))
	}
}

#Preview {
	PullButtonView(
		store: Store(
			initialState: PullButtonReducer.State(
				repositoryPath: "/Users/test/projects/my-project"
			),
			reducer: {
				PullButtonReducer()
			}
		)
	)
	.padding()
}
