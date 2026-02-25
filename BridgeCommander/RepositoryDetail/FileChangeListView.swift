import ComposableArchitecture
import SwiftUI

struct FileChangeListView: View {
	@Bindable
	var store: StoreOf<FileChangeList>

	var body: some View {
		VStack(spacing: 0) {
			SectionHeader(
				title: store.listType == .staged ? "Staged Changes" : "Unstaged Changes",
				count: store.files.count,
				actionTitle: store.listType == .staged ? "Unstage All" : "Stage All",
				action: { store.send(.toggleAllTapped) }
			)
			Divider()

			if store.isLoading {
				ProgressView()
					.frame(maxWidth: .infinity, maxHeight: .infinity)
			}
			else if store.files.isEmpty {
				EmptyStateView(
					title: store.listType == .staged ? "No Staged Changes" : "No Unstaged Changes",
					systemImage: store.listType == .staged ? "tray" : "checkmark.circle",
					description: store.listType == .staged
						? "Files you stage will appear here"
						: "Your working directory is clean"
				)
			}
			else {
				List(
					selection: Binding(
						get: { store.selectedFileIds },
						set: { store.send(.updateSelection($0)) }
					)
				) {
					ForEach(store.files) { file in
						FileChangeRow(
							file: file,
							isStaged: store.listType == .staged,
							selectedFileIds: store.selectedFileIds,
							onToggle: { store.send(.delegate(.toggleAll([file]))) },
							onToggleSelected: { store.send(.toggleSelectedTapped) }
						)
						.tag(file.id)
						.contextMenu { contextMenu(for: file) }
					}
				}
				.listStyle(.plain)
				.onKeyPress(.space) {
					store.send(.spaceKeyPressed)
					return .handled
				}
				.onReturnPress {
					if let file = store.files.first(where: { store.selectedFileIds.contains($0.id) }) {
						store.send(.openInIDE(file))
					}
				}
			}
		}
	}

	@ViewBuilder
	private func contextMenu(for file: FileChange) -> some View {
		if store.selectedFileIds.count > 1, store.selectedFileIds.contains(file.id) {
			if store.listType == .staged {
				Button("Unstage All Selected (\(store.selectedFileIds.count) files)") {
					store.send(.toggleSelectedTapped)
				}
			}
			else {
				let selectedFiles = store.files.filter { store.selectedFileIds.contains($0.id) }
				let allTracked = selectedFiles.allSatisfy { $0.status != .untracked }
				let allUntracked = selectedFiles.allSatisfy { $0.status == .untracked }

				Button("Stage All Selected (\(store.selectedFileIds.count) files)") {
					store.send(.toggleSelectedTapped)
				}
				if allTracked {
					Button("Discard All Selected Changes", role: .destructive) {
						store.send(.delegate(.discardChanges(selectedFiles)))
					}
				}
				if allUntracked {
					Button("Delete All Selected Files", role: .destructive) {
						store.send(.delegate(.deleteUntracked(selectedFiles)))
					}
				}
			}
		}
		else {
			Button("Open in IDE") { store.send(.openInIDE(file)) }

			if store.listType == .staged {
				Button("Unstage") { store.send(.delegate(.toggleAll([file]))) }
			}
			else {
				Button("Stage") { store.send(.delegate(.toggleAll([file]))) }

				if file.status == .untracked {
					Button("Delete File", role: .destructive) {
						store.send(.delegate(.deleteUntracked([file])))
					}
				}
				else if file.status == .conflicted {
					Button("Delete File", role: .destructive) {
						store.send(.delegate(.deleteConflicted([file])))
					}
				}
				else {
					Button("Discard Changes", role: .destructive) {
						store.send(.delegate(.discardChanges([file])))
					}
				}
			}
		}
	}
}
