import SwiftUI

struct FileChangeRow: View {
	let file: FileChange
	let isStaged: Bool
	let selectedFileIds: Set<String>
	let onToggle: () -> Void
	let onToggleSelected: () -> Void
	let onDiscard: (() -> Void)?
	let onDelete: (() -> Void)?

	private var statusColor: Color {
		switch file.status {
		case .added,
		     .untracked:
			.green
		case .modified:
			.orange
		case .deleted:
			.red
		case .copied,
		     .renamed:
			.blue
		case .typeChanged:
			.purple
		}
	}

	var body: some View {
		HStack(spacing: 8) {
			// Checkbox
			Button(action: handleToggle) {
				Image(systemName: isStaged ? "checkmark.square.fill" : "square")
					.foregroundStyle(isStaged ? .blue : .secondary)
			}
			.buttonStyle(.plain)

			// Status Icon
			Image(systemName: file.status.iconName)
				.foregroundStyle(statusColor)
				.imageScale(.small)

			// File Info
			VStack(alignment: .leading, spacing: 2) {
				Text(file.fileName)
					.font(.body)
					.lineLimit(1)

				if !file.directoryPath.isEmpty {
					Text(file.directoryPath)
						.font(.caption)
						.foregroundStyle(.secondary)
						.lineLimit(1)
				}
			}

			Spacer()

			// Actions Menu
			Menu {
				if let onDiscard {
					Button("Discard Changes", role: .destructive) {
						onDiscard()
					}
				}

				if let onDelete {
					Button("Delete File", role: .destructive) {
						onDelete()
					}
				}
			} label: {
				Image(systemName: "ellipsis.circle")
					.foregroundStyle(.secondary)
			}
			.buttonStyle(.plain)
			.opacity(onDiscard != nil || onDelete != nil ? 1 : 0)
		}
		.padding(.vertical, 4)
	}

	private func handleToggle() {
		// If multiple files are selected and this file is among them, toggle all selected
		if selectedFileIds.count > 1, selectedFileIds.contains(file.id) {
			onToggleSelected()
		}
		// Otherwise, toggle just this file
		else {
			onToggle()
		}
	}
}
