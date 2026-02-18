import ComposableArchitecture
import SwiftUI

struct FileDiffViewerView: View {
	let store: StoreOf<FileDiffViewer>

	var body: some View {
		if let diff = store.fileDiff {
			DiffViewer(
				diff: diff,
				isStaged: store.fileIsStaged ?? false,
				onStageHunk: { store.send(.stageHunk($0)) },
				onUnstageHunk: { store.send(.unstageHunk($0)) },
				onDiscardHunk: { store.send(.discardHunk($0)) }
			)
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
