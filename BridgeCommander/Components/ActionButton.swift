import SwiftUI

/// Reusable action button component for repository row actions
struct ActionButton: View {
	enum ButtonIcon {
		case systemImage(String)
		case customImage(String)
	}

	private let icon: ButtonIcon
	private let tooltip: String
	private let color: Color?
	private let action: () -> Void

	var body: some View {
		Button(action: action) {
			switch icon {
			case let .systemImage(name):
				Image(systemName: name)
					.resizable()
					.scaledToFit()
					.frame(width: 20, height: 20)

			case let .customImage(name):
				Image(name)
					.resizable()
					.renderingMode(.template)
					.scaledToFit()
					.frame(width: 20, height: 20)
			}
		}
		.foregroundColor(color ?? .secondary)
		.help(tooltip)
	}

	init(
		icon: ButtonIcon,
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
			icon: .systemImage("doc.on.doc"),
			tooltip: "Copy",
			action: {}
		)
		ActionButton(
			icon: .systemImage("folder"),
			tooltip: "Open in Finder",
			action: {}
		)
		ActionButton(
			icon: .customImage("gitlab"),
			tooltip: "Open GitLab",
			action: {}
		)
	}
	.padding()
}
