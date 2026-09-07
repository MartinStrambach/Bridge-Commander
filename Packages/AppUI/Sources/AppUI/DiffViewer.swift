import AppKit
import SwiftUI

public struct DiffViewer: View {
	/// The per-hunk staging actions offered in a hunk's header.
	public struct HunkActions {
		let isStaged: Bool
		let onStage: (DiffHunk) -> Void
		let onUnstage: (DiffHunk) -> Void
		let onDiscard: (DiffHunk) -> Void
	}

	@State private var selectedLineIDs: Set<DiffLine.ID> = []
	@State private var anchorLineID: DiffLine.ID? = nil
	@FocusState private var isFocused: Bool

	public let diff: FileDiff

	/// Absent for a diff that cannot be staged — a commit's diff is already history, so its
	/// headers carry no actions.
	private let hunkActions: HunkActions?

	private var allLines: [DiffLine] {
		diff.hunks.flatMap(\.lines)
	}

	public init(diff: FileDiff, isStaged: Bool, onStageHunk: @escaping (DiffHunk) -> Void, onUnstageHunk: @escaping (DiffHunk) -> Void, onDiscardHunk: @escaping (DiffHunk) -> Void) {
		self.diff = diff
		self.hunkActions = HunkActions(
			isStaged: isStaged,
			onStage: onStageHunk,
			onUnstage: onUnstageHunk,
			onDiscard: onDiscardHunk
		)
	}

	/// A read-only diff: line selection and copying still work, but no hunk can be staged,
	/// unstaged or discarded.
	public init(diff: FileDiff) {
		self.diff = diff
		self.hunkActions = nil
	}

	public var body: some View {
		if let imageDiff = diff.imageDiff {
			staticContent { ImageDiffView(imageDiff: imageDiff) }
		}
		else if diff.isBinary {
			staticContent { binaryFileView }
		}
		else if diff.hunks.isEmpty {
			staticContent { noChangesView }
		}
		else {
			hunkList
		}
	}

	// MARK: - Hunks

	/// Diff lines are rendered by a `List` rather than a `ScrollView` + `LazyVStack`.
	///
	/// A lazy stack reports its content's height as its own ideal height, so a large diff hands
	/// the enclosing sheet an ideal size of ~10^6 points that keeps changing as rows are measured.
	/// The sheet re-measures on every change, the stack re-estimates, and the two never converge —
	/// the main thread spins in `LazyLayoutViewCache.updateItemPhases` / `LazyStack.measureEstimates`
	/// for minutes (hang reports 2026-09-06 and 2026-09-07). `List` is backed by `NSTableView`: it
	/// recycles rows, its size is independent of its row count, and it never feeds a content-derived
	/// ideal size upwards.
	///
	/// Sections are deliberately not used. A plain-style `List` pins section headers, which would
	/// make hunk headers sticky; emitting the header, lines and footer as sibling rows keeps the
	/// card reading as one scrolling unit.
	private var hunkList: some View {
		List {
			fileHeader
				.diffListRow()

			ForEach(diff.hunks) { hunk in
				HunkHeaderView(hunk: hunk, actions: hunkActions)
					.diffListRow()

				ForEach(hunk.lines) { line in
					DiffLineView(
						line: line,
						oldLineNumber: line.oldLineNumber,
						newLineNumber: line.newLineNumber,
						isSelected: selectedLineIDs.contains(line.id),
						onTap: { modifiers in handleLineTap(line, modifiers: modifiers) }
					)
					.hunkCardRow()
					.diffListRow()
				}

				HunkFooterView()
					.diffListRow()
			}
		}
		.listStyle(.plain)
		// Rows are sized by their content; the default minimum would pad every line and open
		// gaps in the card's side borders.
		.environment(\.defaultMinListRowHeight, 1)
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

	// MARK: - Non-Hunk Content

	/// The file header plus a single block of content, for the diffs that have no lines to list.
	private func staticContent(@ViewBuilder _ content: () -> some View) -> some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 0) {
				fileHeader
				content()
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

	private var noChangesView: some View {
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

	// MARK: - Selection

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

// MARK: - Row Styling

extension View {
	/// Strips the list's own chrome so a diff row occupies its full width with no separator,
	/// leaving the hunk card free to draw the only visible framing.
	fileprivate func diffListRow() -> some View {
		listRowInsets(EdgeInsets())
			.listRowSeparator(.hidden)
	}
}
