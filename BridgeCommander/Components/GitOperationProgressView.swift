import SwiftUI

/// Reusable progress indicator view for git operations
struct GitOperationProgressView: View {
	let text: String
	let color: Color
	let helpText: String

	var body: some View {
		HStack(spacing: 6) {
			ProgressView()
				.controlSize(.small)
				.scaleEffect(0.8)
			Text(text)
				.font(.caption)
				.foregroundColor(.secondary)
		}
		.padding(.horizontal, 8)
		.padding(.vertical, 4)
		.background(color.opacity(0.1))
		.cornerRadius(6)
		.help(helpText)
	}
}

#Preview {
	VStack(spacing: 16) {
		GitOperationProgressView(
			text: "Merging...",
			color: .orange,
			helpText: "Merging master branch..."
		)

		GitOperationProgressView(
			text: "Pulling...",
			color: .blue,
			helpText: "Pulling changes from remote..."
		)
	}
	.padding()
}
