import SwiftUI

/// Reusable button component for header actions
struct HeaderButton: View {
	private let icon: String
	private let tooltip: String
	private let color: Color
	private let action: () -> Void

	var body: some View {
		Button(action: action) {
			Image(systemName: icon)
				.font(.system(size: 16))
				.foregroundColor(color)
				.frame(width: 24, height: 24)
		}
		.frame(width: 30, height: 30)
		.help(tooltip)
	}

	init(
		icon: String,
		tooltip: String,
		color: Color = .gray,
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
		HeaderButton(
			icon: "arrow.clockwise",
			tooltip: "Refresh",
			color: .blue,
			action: {}
		)
		HeaderButton(
			icon: "xmark.circle.fill",
			tooltip: "Clear",
			action: {}
		)
	}
	.padding()
}
