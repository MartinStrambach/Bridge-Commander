import ComposableArchitecture
import SwiftUI
import AppUI
import GitCore

struct FileDiffViewerView: View {
	let store: StoreOf<FileDiffViewer>

	var body: some View {
		if let gitDiff = store.fileDiff {
			DiffViewer(
				diff: gitDiff.toAppUI(),
				isStaged: store.fileIsStaged ?? false,
				onStageHunk: { appUIHunk in
					if let hunk = gitDiff.hunks.first(where: { $0.id == appUIHunk.id }) {
						store.send(.stageHunk(hunk))
					}
				},
				onUnstageHunk: { appUIHunk in
					if let hunk = gitDiff.hunks.first(where: { $0.id == appUIHunk.id }) {
						store.send(.unstageHunk(hunk))
					}
				},
				onDiscardHunk: { appUIHunk in
					if let hunk = gitDiff.hunks.first(where: { $0.id == appUIHunk.id }) {
						store.send(.discardHunk(hunk))
					}
				}
			)
			.id(gitDiff.fileChange.id)
		}
		else {
			EmptyStateView(
				title: "No File Selected",
				systemImage: "doc.text.magnifyingglass",
				description: "Select a file to view its changes"
			)
			.background(Color(nsColor: .textBackgroundColor))
		}
	}
}
