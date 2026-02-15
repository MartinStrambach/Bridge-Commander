import SwiftUI

struct HunkActionButton: View {
	let title: String
	let action: () -> Void

	var body: some View {
		Button(action: action) {
			Text(title)
				.font(.caption)
				.padding(.horizontal, 10)
				.padding(.vertical, 5)
				.background(Color(nsColor: .controlBackgroundColor))
				.foregroundStyle(.primary)
				.cornerRadius(4)
				.overlay(
					RoundedRectangle(cornerRadius: 4)
						.stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
				)
		}
		.buttonStyle(.plain)
	}
}
