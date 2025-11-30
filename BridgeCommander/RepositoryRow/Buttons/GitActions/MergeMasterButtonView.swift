import ComposableArchitecture
import SwiftUI

// MARK: - Merge Master Button View

struct MergeMasterButtonView: View {
	let store: StoreOf<MergeMasterButtonReducer>

	var body: some View {
		Group {
			if store.isMergingMaster {
				GitOperationProgressView(
					text: "Merging...",
					color: .orange,
					helpText: "Merging master branch..."
				)
			}
			else {
				Button {
					store.send(.mergeMasterTapped)
				} label: {
					Label("Merge Master", systemImage: "arrow.triangle.merge")
				}
			}
		}
		.alert(store: store.scope(state: \.$alert, action: \.alert))
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
