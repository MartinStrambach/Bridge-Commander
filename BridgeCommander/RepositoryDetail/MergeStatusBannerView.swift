import ComposableArchitecture
import SwiftUI

struct MergeStatusBannerView: View {
	var store: StoreOf<MergeStatus>

	var body: some View {
		BannerView(
			icon: "arrow.triangle.merge",
			title: "Merge in Progress",
			actionLabel: "Finish Merge",
			actionSystemImage: "checkmark.circle",
			actionHelp: "Complete merge with git commit --no-edit",
			isLoading: store.isLoading,
			onAction: { store.send(.finishMergeButtonTapped) }
		)
	}
}
