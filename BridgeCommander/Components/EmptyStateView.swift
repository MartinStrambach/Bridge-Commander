import SwiftUI

struct EmptyStateView: View {
	let title: String
	let systemImage: String
	let description: String

	var body: some View {
		VStack {
			Spacer()
			ContentUnavailableView(
				title,
				systemImage: systemImage,
				description: Text(description)
			)
			Spacer()
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
	}
}
