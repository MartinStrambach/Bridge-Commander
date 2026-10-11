import SwiftUI

/// How large the repository row's tool buttons (Android Studio, Xcode, Claude Code) are drawn.
/// Set through the `toolButtonSize` environment value; the raw values are what Settings stores.
public enum ToolButtonSize: String, CaseIterable, Sendable {
	/// Icon only, the label left to the tooltip.
	case small
	case medium
	case large

	public var displayName: String {
		switch self {
		case .small: "Small"
		case .medium: "Medium"
		case .large: "Large"
		}
	}

	var buttonSize: CGFloat {
		switch self {
		case .small: 32
		case .medium: 56
		case .large: 65
		}
	}

	var iconSize: CGFloat {
		switch self {
		case .small: 18
		case .medium: 20
		case .large: 25
		}
	}

	var showsLabel: Bool {
		self != .small
	}
}

public extension EnvironmentValues {
	@Entry
	var toolButtonSize: ToolButtonSize = .medium
}

/// Reusable tool button component for repository row tool actions
public struct ToolButton: View {
	public enum ButtonIcon {
		case systemImage(String)
		case customImage(String)
	}

	private let label: String
	private let icon: ButtonIcon
	private let tooltip: String
	private let isProcessing: Bool
	private let tint: Color?
	private let action: () -> Void

	@Environment(\.toolButtonSize)
	private var size

	private var buttonSize: CGFloat { size.buttonSize }
	private var iconSize: CGFloat { size.iconSize }

	public var body: some View {
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

				if size.showsLabel {
					Spacer(minLength: 0)

					Text(label)
						.scaledFont(.caption2)
						.lineLimit(2)
						// "Install & Generate" barely fits two lines at the medium width.
						.minimumScaleFactor(0.8)
						.multilineTextAlignment(.center)
						.fixedSize(horizontal: false, vertical: true)
				}
			}
			.padding(size.showsLabel ? 4 : 0)
			.frame(width: buttonSize, height: buttonSize)
		}
		.buttonStyle(.scaledBordered)
		.fixedSize()
		.tint(tint)
		.disabled(isProcessing)
		.help(tooltip)
	}

	public init(
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
