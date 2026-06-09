import ComposableArchitecture
import SwiftUI
import AppUI

struct DeleteWorktreeButtonView: View {
	@Bindable
	var store: StoreOf<DeleteWorktreeButtonReducer>

	var body: some View {
		ActionButton(
			icon: .systemImage("trash"),
			tooltip: "Remove worktree",
			color: .red,
			action: { store.send(.showConfirmation) }
		)
		.opacity(store.isRemoving ? 0 : 1)
		.overlay {
			if store.isRemoving {
				ProgressView()
					.scaleEffect(0.5)
			}
		}
		.disabled(store.isRemoving)
		.sheet(item: $store.scope(\.$confirmationSheet, action: \.confirmationSheet)) { confirmStore in
			DeleteWorktreeConfirmationView(store: confirmStore)
		}
		.alert($store.scope(\.$errorAlert, action: \.errorAlert))
		.alert($store.scope(\.$derivedDataWarningAlert, action: \.derivedDataWarningAlert))
	}
}
