import SwiftUI

/// Reusable action button component for repository row actions
struct ActionButton: View {
	let icon: String
	let tooltip: String
	let action: () -> Void

	var body: some View {
		Button(action: action) {
			Image(systemName: icon)
				.foregroundColor(.secondary)
				.frame(width: 20, height: 20)
		}
		.help(tooltip)
	}
}

#Preview {
	HStack(spacing: 8) {
		ActionButton(
			icon: "doc.on.doc",
			tooltip: "Copy",
			action: {}
		)
		ActionButton(
			icon: "folder",
			tooltip: "Open in Finder",
			action: {}
		)
	}
	.padding()
}
