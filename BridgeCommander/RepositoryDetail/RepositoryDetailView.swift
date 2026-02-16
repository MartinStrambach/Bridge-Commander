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

			// Main Content
			NavigationSplitView(columnVisibility: .constant(.all)) {
				// Left: File Changes Lists (Staged and Unstaged)
				VSplitView {
					// Top: Staged Changes
					stagedChangesView
						.frame(minHeight: 100)

					// Bottom: Unstaged Changes
					unstagedChangesView
						.frame(minHeight: 100)
				}
				.navigationSplitViewColumnWidth(min: 250, ideal: 350, max: 500)
			} detail: {
				// Right: Diff Viewer
				diffViewerView
			}
		}
		.onKeyPress(.space) {
			store.send(.spaceKeyPressed)
			return .handled
		}
		.task {
			store.send(.loadChanges)
		}
		.onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
			store.send(.loadChanges)
		}
	}

	// MARK: - Staged Changes View

	private var stagedChangesView: some View {
		VStack(spacing: 0) {
			SectionHeader(
				title: "Staged Changes",
				count: store.stagedChanges.count,
				actionTitle: "Unstage All",
				action: {
					store.send(.unstageFiles(store.stagedChanges))
				}
			)
			Divider()

			// List
			if store.stagedChanges.isEmpty {
				EmptyStateView(
					title: "No Staged Changes",
					systemImage: "tray",
					description: "Files you stage will appear here"
				)
			}
			else {
				List(
					selection: Binding(
						get: { store.selectedStagedFileIds },
						set: { store.send(.updateSelection($0, isStaged: true)) }
					)
				) {
					ForEach(store.stagedChanges) { file in
						FileChangeRow(
							file: file,
							isStaged: true,
							selectedFileIds: store.selectedStagedFileIds,
							onToggle: {
								store.send(.unstageFiles([file]))
							},
							onToggleSelected: {
								let selected = store.stagedChanges
									.filter { store.selectedStagedFileIds.contains($0.id) }
								store.send(.unstageFiles(selected))
							}
						)
						.tag(file.id)
						.contextMenu {
							if store.selectedStagedFileIds.count > 1, store.selectedStagedFileIds.contains(file.id) {
								// Multi-selection context menu
								Button("Unstage All Selected (\(store.selectedStagedFileIds.count) files)") {
									let selected = store.stagedChanges
										.filter { store.selectedStagedFileIds.contains($0.id) }
									store.send(.unstageFiles(selected))
								}
							}
							else {
								// Single file context menu
								Button("Open in IDE") {
									store.send(.openFileInIDE(file))
								}

								Button("Unstage") {
									store.send(.unstageFiles([file]))
								}
							}
						}
					}
				}
				.listStyle(.plain)
				.onReturnPress {
					if let file = store.stagedChanges.first(where: { store.selectedStagedFileIds.contains($0.id) }) {
						store.send(.openFileInIDE(file))
					}
				}
			}
		}
	}

	// MARK: - Unstaged Changes View

	private var unstagedChangesView: some View {
		VStack(spacing: 0) {
			SectionHeader(
				title: "Unstaged Changes",
				count: store.unstagedChanges.count,
				actionTitle: "Stage All",
				action: {
					store.send(.stageFiles(store.unstagedChanges))
				}
			)
			Divider()

			// List
			if store.unstagedChanges.isEmpty {
				EmptyStateView(
					title: "No Unstaged Changes",
					systemImage: "checkmark.circle",
					description: "Your working directory is clean"
				)
			}
			else {
				List(
					selection: Binding(
						get: { store.selectedUnstagedFileIds },
						set: { store.send(.updateSelection($0, isStaged: false)) }
					)
				) {
					ForEach(store.unstagedChanges) { file in
						FileChangeRow(
							file: file,
							isStaged: false,
							selectedFileIds: store.selectedUnstagedFileIds,
							onToggle: {
								store.send(.stageFiles([file]))
							},
							onToggleSelected: {
								let selected = store.unstagedChanges
									.filter { store.selectedUnstagedFileIds.contains($0.id) }
								store.send(.stageFiles(selected))
							}
						)
						.tag(file.id)
						.contextMenu {
							if
								store.selectedUnstagedFileIds.count > 1,
								store.selectedUnstagedFileIds.contains(file.id)
							{
								// Multi-selection context menu
								Button("Stage All Selected (\(store.selectedUnstagedFileIds.count) files)") {
									let selected = store.unstagedChanges
										.filter { store.selectedUnstagedFileIds.contains($0.id) }
									store.send(.stageFiles(selected))
								}
							}
							else {
								// Single file context menu
								Button("Open in IDE") {
									store.send(.openFileInIDE(file))
								}

								Button("Stage") {
									store.send(.stageFiles([file]))
								}

								Button("Discard Changes", role: .destructive) {
									store.send(.discardFileChanges(file))
								}

								if file.status == .untracked {
									Button("Delete File", role: .destructive) {
										store.send(.deleteUntrackedFile(file))
									}
								}
							}
						}
					}
				}
				.listStyle(.plain)
				.onReturnPress {
					if
						let file = store.unstagedChanges
							.first(where: { store.selectedUnstagedFileIds.contains($0.id) })
					{
						store.send(.openFileInIDE(file))
					}
				}
			}
		}
	}

	// MARK: - Diff Viewer

	@ViewBuilder
	private var diffViewerView: some View {
		if let diff = store.selectedFileDiff {
			let isStaged = store.selectedFileIsStaged ?? false
			DiffViewer(
				diff: diff,
				isStaged: isStaged,
				onStageHunk: { hunk in
					store.send(.stageHunk(diff.fileChange, hunk))
				},
				onUnstageHunk: { hunk in
					store.send(.unstageHunk(diff.fileChange, hunk))
				},
				onDiscardHunk: { hunk in
					store.send(.discardHunk(diff.fileChange, hunk))
				}
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
