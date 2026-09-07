import SwiftUI

public struct FileChangeRow: View {
	public let file: FileChange
	public let isStaged: Bool

	/// Absent when the row is read-only (a committed change), which also drops the checkbox.
	public let onToggle: (() -> Void)?

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
		case .conflicted:
			.yellow
		}
	}

	public var body: some View {
		HStack(spacing: 8) {
			// Checkbox
			if let onToggle {
				Button(action: onToggle) {
					Image(systemName: isStaged ? "checkmark.square.fill" : "square")
						.foregroundStyle(isStaged ? .blue : .secondary)
				}
				.contentShape(Rectangle())
				.buttonStyle(.plain)
			}

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

			if let addedLines = file.addedLines, let removedLines = file.removedLines {
				LineStatsView(addedLines: addedLines, removedLines: removedLines)
			}
		}
		.padding(.vertical, 4)
	}

	public init(
		file: FileChange,
		isStaged: Bool,
		onToggle: @escaping () -> Void
	) {
		self.file = file
		self.isStaged = isStaged
		self.onToggle = onToggle
	}

	/// A read-only row: status, path and line stats, without the staging checkbox.
	public init(file: FileChange) {
		self.file = file
		self.isStaged = false
		self.onToggle = nil
	}
}
