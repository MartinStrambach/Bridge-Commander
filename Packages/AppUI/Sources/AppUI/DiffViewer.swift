import AppKit
import SwiftUI

public struct DiffViewer: View {
	@State private var selectedLineIDs: Set<DiffLine.ID> = []
	@State private var anchorLineID: DiffLine.ID? = nil
	@FocusState private var isFocused: Bool

	public let diff: FileDiff
	public let isStaged: Bool
	public let onStageHunk: (DiffHunk) -> Void
	public let onUnstageHunk: (DiffHunk) -> Void
	public let onDiscardHunk: (DiffHunk) -> Void

	private var allLines: [DiffLine] {
		diff.hunks.flatMap(\.lines)
	}

	public init(diff: FileDiff, isStaged: Bool, onStageHunk: @escaping (DiffHunk) -> Void, onUnstageHunk: @escaping (DiffHunk) -> Void, onDiscardHunk: @escaping (DiffHunk) -> Void) {
		self.diff = diff
		self.isStaged = isStaged
		self.onStageHunk = onStageHunk
		self.onUnstageHunk = onUnstageHunk
		self.onDiscardHunk = onDiscardHunk
	}

	public var body: some View {
		ScrollView {
			LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
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
							selectedLineIDs: selectedLineIDs,
							onStage: { onStageHunk(hunk) },
							onUnstage: { onUnstageHunk(hunk) },
							onDiscard: { onDiscardHunk(hunk) },
							onLineTap: handleLineTap
						)
					}
				}
			}
		}
		.focusable()
		.focusEffectDisabled()
		.focused($isFocused)
		.onTapGesture { isFocused = true }
		.onKeyPress(.init("c"), phases: .down) { press in
			guard press.modifiers.contains(.command), !selectedLineIDs.isEmpty else {
				return .ignored
			}

			copySelectedLines()
			return .handled
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

	private func handleLineTap(_ line: DiffLine, modifiers: EventModifiers) {
		isFocused = true
		if modifiers.contains(.shift), let anchor = anchorLineID {
			// Range selection from anchor to clicked line
			let lines = allLines
			guard
				let anchorIndex = lines.firstIndex(where: { $0.id == anchor }),
				let clickedIndex = lines.firstIndex(where: { $0.id == line.id })
			else {
				return
			}

			let range = min(anchorIndex, clickedIndex) ... max(anchorIndex, clickedIndex)
			selectedLineIDs = Set(lines[range].map(\.id))
		}
		else if modifiers.contains(.command) {
			// Toggle individual line
			if selectedLineIDs.contains(line.id) {
				selectedLineIDs.remove(line.id)
			}
			else {
				selectedLineIDs.insert(line.id)
			}
			anchorLineID = line.id
		}
		else {
			// Plain click — select only this line
			selectedLineIDs = [line.id]
			anchorLineID = line.id
		}
	}

	private func copySelectedLines() {
		let ordered = allLines.filter { selectedLineIDs.contains($0.id) }
		let text = ordered.map(\.content).joined(separator: "\n")
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(text, forType: .string)
	}

}
