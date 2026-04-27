import AppKit
import AppUI
import ComposableArchitecture
import GitCore
import SwiftUI

struct RepositoryChangesSplitView: View {
	@Bindable
	var store: StoreOf<RepositoryDetail>

	let orientation: TerminalChangesSplitOrientation
	let onOrientationChange: (TerminalChangesSplitOrientation) -> Void
	let onClose: () -> Void

	var body: some View {
		VStack(spacing: 0) {
			header
			Divider()

			if store.mergeStatus.isMergeInProgress {
				MergeStatusBannerView(store: store.scope(state: \.mergeStatus, action: \.mergeStatus))
			}

			NavigationSplitView(columnVisibility: .constant(.all)) {
				allChangesList
				.navigationSplitViewColumnWidth(min: 220, ideal: 300, max: 420)
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
		.sheet(item: $store.scope(state: \.$alert, action: \.alert)) { alertStore in
			ScrollableAlertView(store: alertStore)
		}
		.sheet(item: $store.scope(state: \.$commitSheet, action: \.commitSheet)) { commitStore in
			CommitView(store: commitStore)
		}
	}

	private var header: some View {
		HStack(spacing: 8) {
			Label("Changes", systemImage: "square.and.pencil")
				.font(.headline)

			Spacer()

			if !store.staged.files.isEmpty {
				Button {
					store.send(.commitButtonTapped)
				} label: {
					Image(systemName: "checkmark.circle")
				}
				.help("Commit staged changes")
			}

			if store.isPushing || store.unpushedCommitsCount > 0 {
				Button {
					store.send(.pushButtonTapped)
				} label: {
					Image(systemName: "arrow.up.circle.fill")
						.opacity(store.isPushing ? 0 : 1)
						.overlay {
							if store.isPushing {
								ProgressView()
									.scaleEffect(0.4)
							}
						}
				}
				.tint(.orange)
				.help(store.isPushing
					? "Pushing commits to remote..."
					: "Push \(store.unpushedCommitsCount) unpushed commit(s) to remote")
				.disabled(store.isPushing)
			}

			Button {
				store.send(.loadChanges)
			} label: {
				Image(systemName: "arrow.clockwise")
					.opacity(store.isLoadingChanges ? 0 : 1)
					.overlay {
						if store.isLoadingChanges {
							ProgressView()
								.scaleEffect(0.4)
						}
					}
			}
			.help(store.isLoadingChanges ? "Refreshing changes..." : "Refresh changes")
			.disabled(store.isLoadingChanges)

			orientationButton(.vertical)
			orientationButton(.horizontal)

			Button(action: onClose) {
				Image(systemName: "xmark")
			}
			.help("Close changes split")
		}
		.buttonStyle(.borderless)
		.controlSize(.small)
		.padding(.horizontal, 10)
		.padding(.vertical, 8)
		.background(Color(nsColor: .windowBackgroundColor))
	}

	private func orientationButton(_ value: TerminalChangesSplitOrientation) -> some View {
		Button {
			onOrientationChange(value)
		} label: {
			Image(systemName: value.systemImage)
				.foregroundColor(orientation == value ? .accentColor : .secondary)
		}
		.help(value.displayName)
		.disabled(orientation == value)
	}

	private var allChangeItems: [ChangesSplitFileItem] {
		store.unstaged.files.map { ChangesSplitFileItem(file: $0, isStaged: false) }
			+ store.staged.files.map { ChangesSplitFileItem(file: $0, isStaged: true) }
	}

	private var allChangesList: some View {
		VStack(spacing: 0) {
			SectionHeader(
				title: "All Changes",
				count: allChangeItems.count
			)
			Divider()

			if store.staged.isLoading || store.unstaged.isLoading {
				ProgressView()
					.frame(maxWidth: .infinity, maxHeight: .infinity)
			}
			else if allChangeItems.isEmpty {
				EmptyStateView(
					title: "No Changes",
					systemImage: "checkmark.circle",
					description: "Your working directory is clean"
				)
			}
			else {
				List {
					ForEach(allChangeItems) { item in
						FileChangeRow(
							file: item.file.toAppUI(),
							isStaged: item.isStaged,
							selectedFileIds: selectedFileIds(for: item),
							onToggle: { toggle(item) },
							onToggleSelected: { toggleSelected(item) }
						)
						.background(isSelected(item) ? Color.accentColor.opacity(0.15) : Color.clear)
						.contentShape(Rectangle())
						.onTapGesture {
							store.send(.selectFile(item.file, isStaged: item.isStaged))
						}
					}
				}
				.listStyle(.plain)
			}
		}
	}

	private func isSelected(_ item: ChangesSplitFileItem) -> Bool {
		selectedFileIds(for: item).contains(item.file.id)
	}

	private func selectedFileIds(for item: ChangesSplitFileItem) -> Set<String> {
		item.isStaged ? store.staged.selectedFileIds : store.unstaged.selectedFileIds
	}

	private func toggle(_ item: ChangesSplitFileItem) {
		if item.isStaged {
			store.send(.staged(.delegate(.toggleAll([item.file]))))
		}
		else {
			store.send(.unstaged(.delegate(.toggleAll([item.file]))))
		}
	}

	private func toggleSelected(_ item: ChangesSplitFileItem) {
		let selectedIds = selectedFileIds(for: item)
		let files = item.isStaged
			? store.staged.files.filter { selectedIds.contains($0.id) }
			: store.unstaged.files.filter { selectedIds.contains($0.id) }

		if item.isStaged {
			store.send(.staged(.delegate(.toggleAll(files))))
		}
		else {
			store.send(.unstaged(.delegate(.toggleAll(files))))
		}
	}
}

private struct ChangesSplitFileItem: Identifiable, Equatable {
	let file: GitCore.FileChange
	let isStaged: Bool

	var id: String {
		Self.id(for: file.id, isStaged: isStaged)
	}

	static func id(for fileId: String, isStaged: Bool) -> String {
		"\(isStaged ? "staged" : "unstaged"):\(fileId)"
	}
}
