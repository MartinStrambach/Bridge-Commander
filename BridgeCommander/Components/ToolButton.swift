import ComposableArchitecture
import SwiftUI

/// Reusable tool button component for repository row tool actions
struct ToolButton: View {
	enum ButtonIcon {
		case systemImage(String)
		case customImage(String)
	}

	private let label: String
	private let icon: ButtonIcon
	private let tooltip: String
	private let isProcessing: Bool
	private let tint: Color?
	private let action: () -> Void

	private let buttonSize: CGFloat = 65
	private let iconSize: CGFloat = 25

	var body: some View {
		Button(action: action) {
			VStack(spacing: 4) {
				if isProcessing {
					ProgressView()
						.frame(width: iconSize, height: iconSize)
						.controlSize(.small)
				}
				else {
					Group {
						switch icon {
						case let .systemImage(name):
							Image(systemName: name)
								.resizable()
								.renderingMode(.template)

						case let .customImage(name):
							Image(name)
								.resizable()
								.renderingMode(.template)
						}
					}
					.scaledToFit()
					.frame(width: iconSize, height: iconSize)
					.foregroundStyle(tint ?? .primary)
				}

				Spacer(minLength: 0)

				Text(label)
					.font(.caption2)
					.lineLimit(2)
					.multilineTextAlignment(.center)
					.fixedSize(horizontal: false, vertical: true)
			}
			.padding(4)
			.frame(width: buttonSize, height: buttonSize)
		}
		.buttonStyle(.bordered)
		.fixedSize()
		.tint(tint)
		.disabled(isProcessing)
		.help(tooltip)
	}

	init(
		label: String,
		icon: ButtonIcon,
		tooltip: String,
		isProcessing: Bool = false,
		tint: Color? = nil,
		action: @escaping () -> Void
	) {
		self.label = label
		self.icon = icon
		self.tooltip = tooltip
		self.isProcessing = isProcessing
		self.tint = tint
		self.action = action
	}

}

#Preview {
	VStack(spacing: 16) {
		ToolButton(
			label: "Terminal",
			icon: .systemImage("terminal"),
			tooltip: "Open terminal",
			action: {}
		)

		ToolButton(
			label: "Opening",
			icon: .systemImage("hammer"),
			tooltip: "Opening Xcode...",
			isProcessing: true,
			tint: .orange,
			action: {}
		)

		ToolButton(
			label: "Android Studio",
			icon: .customImage("android"),
			tooltip: "Open in Android Studio",
			tint: .green,
			action: {}
		)
	}
	.padding()
}
