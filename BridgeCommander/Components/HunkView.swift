import SwiftUI

struct HunkView: View {
	let hunk: DiffHunk
	let isStaged: Bool
	let selectedLineIDs: Set<DiffLine.ID>
	let onStage: () -> Void
	let onUnstage: () -> Void
	let onDiscard: () -> Void
	let onLineTap: (DiffLine, EventModifiers) -> Void

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			// Hunk Header with Actions
			HStack {
				Text(hunk.header)
					.font(.system(.caption, design: .monospaced))
					.foregroundStyle(.secondary)

				Spacer()

				// Hunk Actions
				HStack(spacing: 6) {
					if !isStaged {
						HunkActionButton(title: "Stage", action: onStage)
					}

					if isStaged {
						HunkActionButton(title: "Unstage", action: onUnstage)
					}

					if !isStaged {
						HunkActionButton(title: "Discard", action: onDiscard)
					}
				}
			}
			.padding(.horizontal, 12)
			.padding(.vertical, 8)
			.background(Color(nsColor: .controlBackgroundColor))

			// Hunk Lines
			LazyVStack(spacing: 0) {
				ForEach(hunk.lines) { line in
					DiffLineView(
						line: line,
						oldLineNumber: line.oldLineNumber,
						newLineNumber: line.newLineNumber,
						isSelected: selectedLineIDs.contains(line.id),
						onTap: { modifiers in onLineTap(line, modifiers) }
					)
				}
			}
		}
		.background(Color(nsColor: .textBackgroundColor))
		.cornerRadius(6)
		.overlay(
			RoundedRectangle(cornerRadius: 6)
				.stroke(Color(nsColor: .separatorColor), lineWidth: 1)
		)
		.padding(.horizontal, 12)
		.padding(.vertical, 8)
	}

}
