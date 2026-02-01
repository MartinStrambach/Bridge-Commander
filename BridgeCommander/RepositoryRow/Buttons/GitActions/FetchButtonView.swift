import ComposableArchitecture
import SwiftUI

// MARK: - Fetch Button View

struct FetchButtonView: View {
	let store: StoreOf<FetchButtonReducer>

	var body: some View {
		Button {
			store.send(.fetchTapped)
		} label: {
			Label("Fetch", systemImage: "arrow.down.circle.dotted")
		}
	}
}

#Preview {
	FetchButtonView(
		store: Store(
			initialState: FetchButtonReducer.State(
				repositoryPath: "/Users/test/projects/my-project"
			),
			reducer: {
				FetchButtonReducer()
			}
		)
	)
	.padding()
}
