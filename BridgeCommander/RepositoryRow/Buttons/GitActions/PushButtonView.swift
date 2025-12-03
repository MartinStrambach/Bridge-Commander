import ComposableArchitecture
import SwiftUI

// MARK: - Push Button View

struct PushButtonView: View {
	let store: StoreOf<PushButtonReducer>

	var body: some View {
		Button {
			store.send(.pushTapped)
		} label: {
			Label("Push", systemImage: "arrow.up.circle")
		}
	}
}

#Preview {
	PushButtonView(
		store: Store(
			initialState: PushButtonReducer.State(
				repositoryPath: "/Users/test/projects/my-project"
			),
			reducer: {
				PushButtonReducer()
			}
		)
	)
	.padding()
}
