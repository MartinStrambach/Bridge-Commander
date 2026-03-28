import SwiftUI

/// A reusable colored banner with an icon, title, optional subtitle, an optional action button, and an optional dismiss
/// button.
public struct BannerView: View {
	public let icon: String
	public let title: String
	public var subtitle: String?
	public var color: Color = .orange
	public var actionLabel: String?
	public var actionSystemImage: String?
	public var actionHelp: String?
	public var isLoading = false
	public var onAction: (() -> Void)?
	public var onDismiss: (() -> Void)?

	public init(
		icon: String,
		title: String,
		subtitle: String? = nil,
		color: Color = .orange,
		actionLabel: String? = nil,
		actionSystemImage: String? = nil,
		actionHelp: String? = nil,
		isLoading: Bool = false,
		onAction: (() -> Void)? = nil,
		onDismiss: (() -> Void)? = nil
	) {
		self.icon = icon
		self.title = title
		self.subtitle = subtitle
		self.color = color
		self.actionLabel = actionLabel
		self.actionSystemImage = actionSystemImage
		self.actionHelp = actionHelp
		self.isLoading = isLoading
		self.onAction = onAction
		self.onDismiss = onDismiss
	}

	public var body: some View {
		HStack(spacing: 8) {
			Image(systemName: icon)
				.foregroundStyle(color)

			VStack(alignment: .leading, spacing: 2) {
				Text(title)
					.font(.headline)
					.foregroundStyle(color)

				if let subtitle {
					Text(subtitle)
						.font(.caption)
						.foregroundStyle(.secondary)
				}
			}

			Spacer()

			if let actionLabel, let onAction {
				Button(action: onAction) {
					if let actionSystemImage {
						Label(actionLabel, systemImage: actionSystemImage)
					}
					else {
						Text(actionLabel)
					}
				}
				.buttonStyle(.bordered)
				.tint(color)
				.help(actionHelp ?? "")
				.opacity(isLoading ? 0 : 1)
				.overlay {
					if isLoading {
						ProgressView()
							.scaleEffect(0.5)
					}
				}
				.disabled(isLoading)
			}

			if let onDismiss {
				Button(action: onDismiss) {
					Image(systemName: "xmark")
						.foregroundStyle(.secondary)
				}
				.buttonStyle(.plain)
				.help("Dismiss")
			}
		}
		.padding(.horizontal)
		.padding(.vertical, 10)
		.background(color.opacity(0.1))
	}
}

#Preview {
	VStack(spacing: 0) {
		BannerView(
			icon: "arrow.triangle.merge",
			title: "Merge in Progress",
			actionLabel: "Finish Merge",
			actionSystemImage: "checkmark.circle",
			actionHelp: "Complete merge with git commit --no-edit",
			onAction: {}
		)

		BannerView(
			icon: "exclamationmark.triangle.fill",
			title: "Automation permission required",
			subtitle: "Some features may not work correctly.",
			actionLabel: "Open System Settings",
			onAction: {},
			onDismiss: {}
		)
	}
	.frame(width: 600)
}
