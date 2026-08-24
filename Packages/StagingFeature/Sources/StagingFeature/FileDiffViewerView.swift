import AppUI
import ComposableArchitecture
import GitCore
import SwiftUI

struct FileDiffViewerView: View {
	let store: StoreOf<FileDiffViewer>

	var body: some View {
		if let diff = store.displayDiff {
			DiffViewer(
				diff: diff,
				isStaged: store.fileIsStaged ?? false,
				onStageHunk: { store.send(.stageHunk(hunkId: $0.id)) },
				onUnstageHunk: { store.send(.unstageHunk(hunkId: $0.id)) },
				onDiscardHunk: { store.send(.discardHunk(hunkId: $0.id)) }
			)
			.id(diff.fileChange.id)
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
