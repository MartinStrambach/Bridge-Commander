import ComposableArchitecture
import SwiftUI

// MARK: - Merge Master Button View

struct MergeMasterButtonView: View {
	let store: StoreOf<MergeMasterButtonReducer>

	var body: some View {
		Button {
			store.send(.mergeMasterTapped)
		} label: {
			Label("Merge Master", systemImage: "arrow.triangle.merge")
		}
	}
}

#Preview {
	MergeMasterButtonView(
		store: Store(
			initialState: MergeMasterButtonReducer.State(
				repositoryPath: "/Users/test/projects/my-project"
			),
			reducer: {
				MergeMasterButtonReducer()
			}
		)
	)
	.padding()
}
