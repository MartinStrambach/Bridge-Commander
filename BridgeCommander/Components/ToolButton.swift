import ComposableArchitecture
import SwiftUI

/// Reusable tool button component for repository row tool actions
struct ToolButton: View {
	enum ButtonIcon {
		case systemImage(String)
		case customImage(String)
	}

	@Shared(.isAbbreviated)
	private var isAbbreviated = false

	private let label: String
	private let icon: ButtonIcon
	private let tooltip: String
	private let isProcessing: Bool
	private let tint: Color?
	private let action: () -> Void

	private let minWidthFull: CGFloat = 110
	private let minWidthCompact: CGFloat = 50
	private let iconHeight: CGFloat = 13

	var body: some View {
		Group {
			if isProcessing {
				HStack(spacing: 8) {
					ProgressView()
					Text(label)
						.font(.body)
				}
				.frame(minWidth: isAbbreviated ? minWidthCompact : minWidthFull)
				.buttonStyle(.borderedProminent)
			}
			else {
				Button(action: action) {
					Label {
						Text(label)
					} icon: {
						switch icon {
						case let .systemImage(name):
							Image(systemName: name)
								.resizable()
								.renderingMode(.template)
								.scaledToFit()
								.frame(height: iconHeight)
								.foregroundStyle(tint ?? .white)

						case let .customImage(name):
							Image(name)
								.resizable()
								.renderingMode(.template)
								.scaledToFit()
								.frame(height: iconHeight)
								.foregroundStyle(tint ?? .white)
						}
					}
					.frame(height: 20)
					.frame(minWidth: isAbbreviated ? minWidthCompact : minWidthFull)
				}
				.buttonStyle(.bordered)
			}
		}
		.tint(tint)
		.controlSize(.small)
		.fixedSize(horizontal: true, vertical: false)
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
