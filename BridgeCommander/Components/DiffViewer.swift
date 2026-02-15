import SwiftUI

struct DiffViewer: View {
	let diff: FileDiff
	let isStaged: Bool
	let onStageHunk: (DiffHunk) -> Void
	let onUnstageHunk: (DiffHunk) -> Void
	let onDiscardHunk: (DiffHunk) -> Void

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 0) {
				// Header
				fileHeader

				if diff.isBinary {
					binaryFileView
				}
				else if diff.hunks.isEmpty {
					VStack(spacing: 8) {
						Image(systemName: "doc.plaintext")
							.font(.system(size: 48))
							.foregroundStyle(.secondary)

						Text("No Changes to Display")
							.font(.headline)

						Text("The file has no viewable differences")
							.font(.caption)
							.foregroundStyle(.secondary)
					}
					.frame(maxWidth: .infinity, maxHeight: .infinity)
					.padding(.vertical, 60)
				}
				else {
					// Hunks
					ForEach(diff.hunks) { hunk in
						HunkView(
							hunk: hunk,
							isStaged: isStaged,
							onStage: { onStageHunk(hunk) },
							onUnstage: { onUnstageHunk(hunk) },
							onDiscard: { onDiscardHunk(hunk) }
						)
					}
				}
			}
		}
	}

	private var fileHeader: some View {
		VStack(alignment: .leading, spacing: 4) {
			HStack {
				Image(systemName: diff.fileChange.status.iconName)
					.foregroundStyle(.secondary)

				Text(diff.fileChange.path)
					.font(.headline)

				Spacer()

				Text(diff.fileChange.status.displayName)
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			.padding()

			Divider()
		}
		.background(Color(nsColor: .controlBackgroundColor))
	}

	private var binaryFileView: some View {
		VStack(spacing: 8) {
			Image(systemName: "doc.badge.ellipsis")
				.font(.system(size: 48))
				.foregroundStyle(.secondary)

			Text("Binary File")
				.font(.headline)

			Text("Cannot display diff for binary files")
				.font(.caption)
				.foregroundStyle(.secondary)
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.padding(.vertical, 60)
	}
}
