import SwiftUI

/// Reusable action button component for repository row actions
struct ActionButton: View {
	let icon: String
	let tooltip: String
	let color: Color?
	let action: () -> Void

	var body: some View {
		Button(action: action) {
			Image(systemName: icon)
				.foregroundColor(color ?? .secondary)
				.frame(width: 20, height: 20)
		}
		.help(tooltip)
	}

	init(
		icon: String,
		tooltip: String,
		color: Color? = nil,
		action: @escaping () -> Void
	) {
		self.icon = icon
		self.tooltip = tooltip
		self.color = color
		self.action = action
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
