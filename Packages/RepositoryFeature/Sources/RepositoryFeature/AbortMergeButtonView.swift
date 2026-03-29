import ComposableArchitecture
import SwiftUI

// MARK: - Abort Merge Button View

struct AbortMergeButtonView: View {
	let store: StoreOf<AbortMergeButtonReducer>

	var body: some View {
		Button(role: .destructive) {
			store.send(.abortMergeTapped)
		} label: {
			Label("Abort Merge", systemImage: "xmark.circle")
		}
	}
}

#Preview {
	AbortMergeButtonView(
		store: Store(
			initialState: AbortMergeButtonReducer.State(
				repositoryPath: "/Users/test/projects/my-project"
			),
			reducer: {
				AbortMergeButtonReducer()
			}
		)
	)
	.padding()
}
