import ComposableArchitecture
import SwiftUI

struct MergeStatusBannerView: View {
	var store: StoreOf<MergeStatus>

	var body: some View {
		HStack(spacing: 8) {
			Image(systemName: "arrow.triangle.merge")
				.foregroundStyle(.orange)
			Text("Merge in Progress")
				.font(.headline)
				.foregroundStyle(.orange)
			Spacer()
			Button {
				store.send(.finishMergeButtonTapped)
			} label: {
				Label("Finish Merge", systemImage: "checkmark.circle")
			}
			.buttonStyle(.borderedProminent)
			.tint(.orange)
			.help("Complete merge with git commit --no-edit")
		}
		.padding(.horizontal)
		.padding(.vertical, 12)
		.background(Color.orange.opacity(0.1))
	}
}
