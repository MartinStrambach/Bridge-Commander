import SwiftUI

/// A reusable colored banner with an icon, title, optional subtitle, an optional action button, and an optional dismiss
/// button.
struct BannerView: View {
	let icon: String
	let title: String
	var subtitle: String?
	var color: Color = .orange
	var actionLabel: String?
	var actionSystemImage: String?
	var actionHelp: String?
	var isLoading = false
	var onAction: (() -> Void)?
	var onDismiss: (() -> Void)?

	var body: some View {
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

			if isLoading {
				ProgressView()
					.scaleEffect(0.7)
			}
			else if let actionLabel, let onAction {
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
