import AppKit
import ComposableArchitecture
import SwiftUI

struct RepositoryDetailView: View {
	@Bindable
	var store: StoreOf<RepositoryDetail>

	var body: some View {
		VStack(spacing: 0) {
			// Custom Header
			HStack {
				Text("Repository Changes")
					.font(.title2)
					.fontWeight(.semibold)

				Spacer()

				if !store.staged.files.isEmpty {
					Button {
						store.send(.commitButtonTapped)
					} label: {
						Label("Commit", systemImage: "checkmark.circle")
					}
					.help("Commit staged changes")
				}

				Button {
					store.send(.openTerminalButtonTapped)
				} label: {
					Label("Terminal", systemImage: "terminal")
				}
				.help("Open in Terminal")

				Button {
					store.send(.loadChanges)
				} label: {
					Image(systemName: "arrow.clockwise")
				}
				.keyboardShortcut("r", modifiers: .command)
				.help("Refresh changes (⌘R)")

				Button("Close") {
					store.send(.cancelButtonTapped)
				}
				.keyboardShortcut(.cancelAction)
			}
			.padding()
			.background(Color(nsColor: .windowBackgroundColor))

			Divider()

			// Merge Status Banner
			if store.mergeStatus.isMergeInProgress {
				MergeStatusBannerView(store: store.scope(state: \.mergeStatus, action: \.mergeStatus))
			}

			// Main Content
			NavigationSplitView(columnVisibility: .constant(.all)) {
				// Left: File Changes Lists (Staged and Unstaged)
				VSplitView {
					FileChangeListView(store: store.scope(state: \.staged, action: \.staged))
						.frame(minHeight: 100)
					FileChangeListView(store: store.scope(state: \.unstaged, action: \.unstaged))
						.frame(minHeight: 100)
				}
				.navigationSplitViewColumnWidth(min: 250, ideal: 350, max: 500)
			} detail: {
				FileDiffViewerView(store: store.scope(state: \.diffViewer, action: \.diffViewer))
			}
		}
		.task {
			store.send(.loadChanges)
		}
		.onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
			store.send(.loadChanges)
		}
		.sheet(item: $store.scope(state: \.alert, action: \.alert)) { alertStore in
			ScrollableAlertView(store: alertStore)
		}
		.sheet(item: $store.scope(state: \.commitSheet, action: \.commitSheet)) { commitStore in
			CommitView(store: commitStore)
		}
	}
}

// MARK: - Preview

#Preview {
	RepositoryDetailView(
		store: Store(
			initialState: RepositoryDetail.State(
				repositoryPath: "/Users/test/repo"
			)
		) {
			RepositoryDetail()
		}
	)
}
