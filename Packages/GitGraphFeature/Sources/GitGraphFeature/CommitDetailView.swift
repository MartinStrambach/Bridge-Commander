import AppKit
import AppUI
import ComposableArchitecture
import DiffModelMapping
import GitCore
import SwiftUI

/// The bottom pane of the commit graph: the selected commit's files on the left,
/// the selected file's diff on the right.
struct CommitDetailView: View {
	let store: StoreOf<CommitDetailReducer>
	let onClose: () -> Void

	var body: some View {
		VStack(spacing: 0) {
			header
			Divider()

			HSplitView {
				fileList
					.frame(minWidth: 200, idealWidth: 320, maxWidth: 500)
				diffPane
					.frame(minWidth: 300, maxWidth: .infinity)
			}
		}
		.background(Color(nsColor: .windowBackgroundColor))
	}

	// MARK: - Header

	private var header: some View {
		HStack(alignment: .top, spacing: 8) {
			commitSummary

			Spacer()

			Button {
				onClose()
			} label: {
				Image(systemName: "xmark")
			}
			.buttonStyle(.borderless)
			.help("Hide the commit diff")
		}
		.padding(.horizontal, 12)
		.padding(.vertical, 8)
	}

	private var commitSummary: some View {
		VStack(alignment: .leading, spacing: 4) {
			Text(store.commit.subject)
				.font(.headline)
				.lineLimit(2)
				.textSelection(.enabled)

			HStack(spacing: 6) {
				Text(store.commit.author)
				Text("·")
				Text(store.commit.date, format: .dateTime.day().month(.abbreviated).year().hour().minute())
				Text("·")
				Text(store.commit.shortHash)
					.font(.system(.caption, design: .monospaced))

				if store.commit.isMerge {
					Text("·")
					// The pane shows the diff against the first parent, which is what git itself
					// prints for a merge — worth saying so, since it hides the merged-in side.
					Text("merge, diffed against first parent")
						.italic()
				}
			}
			.font(.caption)
			.foregroundStyle(.secondary)
			.lineLimit(1)
		}
	}

	// MARK: - File List

	private var fileList: some View {
		VStack(spacing: 0) {
			SectionHeader(title: "Changed Files", count: store.files.count)
			Divider()

			if store.isLoadingFiles {
				ProgressView()
					.frame(maxWidth: .infinity, maxHeight: .infinity)
			}
			else if store.hasNoChanges {
				EmptyStateView(
					title: "No Changes",
					systemImage: "doc.plaintext",
					description: "This commit changes no files against its first parent"
				)
			}
			else {
				List(
					selection: Binding(
						get: { store.selectedFileId },
						set: { store.send(.fileSelected($0)) }
					)
				) {
					ForEach(store.files) { file in
						FileChangeRow(file: file.toAppUI())
							.tag(file.id)
					}
				}
				.listStyle(.plain)
			}
		}
		.background(Color(nsColor: .textBackgroundColor))
	}

	// MARK: - Diff Pane

	@ViewBuilder
	private var diffPane: some View {
		if let diff = store.displayDiff {
			DiffViewer(diff: diff)
				.id(diff.fileChange.id)
				.background(Color(nsColor: .textBackgroundColor))
		}
		else if store.isLoadingDiff {
			ProgressView()
				.frame(maxWidth: .infinity, maxHeight: .infinity)
				.background(Color(nsColor: .textBackgroundColor))
		}
		else {
			EmptyStateView(
				title: "No File Selected",
				systemImage: "doc.text.magnifyingglass",
				description: "Select a file to view what this commit changed in it"
			)
			.background(Color(nsColor: .textBackgroundColor))
		}
	}
}
