import SwiftUI

/// Icon button for the list header. Borderless, with a round highlight under the pointer, so a run
/// of them reads as one control when the caller groups them (the list header puts them in glass
/// capsules).
public struct HeaderButton: View {
	private let icon: String
	private let tooltip: String
	private let color: Color
	private let action: () -> Void

	@State
	private var isHovered = false

	public var body: some View {
		Button(action: action) {
			Image(systemName: icon)
				.font(.system(size: 14, weight: .medium))
				.foregroundStyle(color)
				.frame(width: 28, height: 28)
				.background(Color.primary.opacity(isHovered ? 0.1 : 0), in: Circle())
				.contentShape(Circle())
		}
		.buttonStyle(.plain)
		.onHover { isHovered = $0 }
		.animation(.easeOut(duration: 0.12), value: isHovered)
		.help(tooltip)
	}

	public init(
		icon: String,
		tooltip: String,
		color: Color = .secondary,
		action: @escaping () -> Void
	) {
		self.icon = icon
		self.tooltip = tooltip
		self.color = color
		self.action = action
	}

}

#Preview {
	HStack(spacing: 2) {
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
	.padding(3)
	.glassEffect(.regular, in: .capsule)
	.padding()
}
