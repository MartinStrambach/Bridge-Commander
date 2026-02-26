import ComposableArchitecture
import SwiftUI

struct DeleteWorktreeButtonView: View {
	@Bindable
	var store: StoreOf<DeleteWorktreeButtonReducer>

	var body: some View {
		Group {
			if store.isRemoving {
				ProgressView()
					.scaleEffect(0.5)
			}
			else {
				ActionButton(
					icon: .systemImage("trash"),
					tooltip: "Remove worktree",
					color: .red,
					action: { store.send(.showConfirmation) }
				)
			}
		}
		.sheet(item: $store.scope(state: \.confirmationSheet, action: \.confirmationSheet)) { confirmStore in
			DeleteWorktreeConfirmationView(store: confirmStore)
		}
		.alert($store.scope(state: \.errorAlert, action: \.errorAlert))
		.alert($store.scope(state: \.derivedDataWarningAlert, action: \.derivedDataWarningAlert))
	}
}
