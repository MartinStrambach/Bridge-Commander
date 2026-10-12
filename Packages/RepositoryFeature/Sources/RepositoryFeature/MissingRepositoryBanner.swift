import AppKit
import AppUI
import SwiftUI

/// Shown for a tracked repository whose folder a scan did not find: deleted, renamed where its
/// bookmark could not follow, or on a volume that is not mounted. Styled like `BannerView`, which
/// offers only one action.
struct MissingRepositoryBanner: View {
	let path: String
	/// Called with the folder the user picked as where the repository is now.
	let onLocate: (String) -> Void
	let onRemove: () -> Void

	private let color = Color.orange

	var body: some View {
		HStack(spacing: 8) {
			Image(systemName: "folder.badge.questionmark")
				.foregroundStyle(color)

			VStack(alignment: .leading, spacing: 2) {
				Text("“\(URL(fileURLWithPath: path).lastPathComponent)” was not found")
					.scaledFont(.headline)
					.foregroundStyle(color)

				Text(path)
					.scaledFont(.caption)
					.foregroundStyle(.secondary)
					.lineLimit(1)
					.truncationMode(.middle)
					.textSelection(.enabled)
			}

			Spacer()

			Button("Locate…", action: locate)
				.buttonStyle(.scaledBordered)
				.tint(color)
				.help("Pick the folder the repository is in now")

			Button("Remove", action: onRemove)
				.buttonStyle(.scaledBordered)
				.help("Stop tracking this repository")
		}
		.padding(.horizontal)
		.padding(.vertical, 10)
		.background(color.opacity(0.1))
	}

	private func locate() {
		let panel = NSOpenPanel()
		panel.canChooseFiles = false
		panel.canChooseDirectories = true
		panel.allowsMultipleSelection = false
		panel.message = "Select the folder “\(URL(fileURLWithPath: path).lastPathComponent)” is in now"
		// Start beside where it was: a renamed folder is usually still there.
		panel.directoryURL = URL(fileURLWithPath: path).deletingLastPathComponent()

		if panel.runModal() == .OK, let url = panel.url {
			onLocate(url.path)
		}
	}
}
