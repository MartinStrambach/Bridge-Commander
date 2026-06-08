import SwiftUI

public struct FileChangeRow: View {
	public let file: FileChange
	public let isStaged: Bool
	public let onToggle: () -> Void

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
			Button(action: onToggle) {
				Image(systemName: isStaged ? "checkmark.square.fill" : "square")
					.foregroundStyle(isStaged ? .blue : .secondary)
			}
			.contentShape(Rectangle())
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
}
