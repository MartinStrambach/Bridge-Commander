import ComposableArchitecture
import SwiftUI

// MARK: - Checkout Default Branch Button View

struct CheckoutDefaultBranchButtonView: View {
	let store: StoreOf<CheckoutDefaultBranchButtonReducer>

	var body: some View {
		Button {
			store.send(.checkoutTapped)
		} label: {
			Label(
				"Checkout \(store.defaultBranch.isEmpty ? "default branch" : store.defaultBranch)",
				systemImage: "arrow.triangle.branch"
			)
		}
	}
}

#Preview {
	CheckoutDefaultBranchButtonView(
		store: Store(
			initialState: CheckoutDefaultBranchButtonReducer.State(
				repositoryPath: "/Users/test/projects/my-project"
			),
			reducer: {
				CheckoutDefaultBranchButtonReducer()
			}
		)
	)
	.padding()
}
