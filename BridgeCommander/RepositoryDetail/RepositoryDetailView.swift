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
			HSplitView {
				// Left: File Changes Lists (Staged and Unstaged)
				VSplitView {
					// Top: Staged Changes
					stagedChangesView
						.frame(minHeight: 100)

					// Bottom: Unstaged Changes
					unstagedChangesView
						.frame(minHeight: 100)
				}
				.frame(minWidth: 250, idealWidth: 350)

				// Right: Diff Viewer
				diffViewerView
					.frame(minWidth: 400)
			}
			.frame(maxHeight: .infinity)
		}
		.onKeyPress(.space) {
			store.send(.spaceKeyPressed)
			return .handled
		}
		.task {
			store.send(.loadChanges)
		}
	}

	// MARK: - Staged Changes View

	private var stagedChangesView: some View {
		VStack(spacing: 0) {
			SectionHeader(title: "Staged Changes", count: store.stagedChanges.count)
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
							},
							onDiscard: nil,
							onDelete: nil
						)
						.tag(file.id)
					}
				}
				.listStyle(.plain)
			}
		}
	}

	// MARK: - Unstaged Changes View

	private var unstagedChangesView: some View {
		VStack(spacing: 0) {
			SectionHeader(title: "Unstaged Changes", count: store.unstagedChanges.count)
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
							},
							onDiscard: {
								store.send(.discardFileChanges(file))
							},
							onDelete: file.status == .untracked ? {
								store.send(.deleteUntrackedFile(file))
							} : nil
						)
						.tag(file.id)
					}
				}
				.listStyle(.plain)
			}
		}
		.overlay {
			if store.isLoading {
				ProgressView("Loading changes...")
					.scaleEffect(0.5)
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
					store.send(.discardHunk(diff.fileChange, hunk, isStaged: isStaged))
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

// MARK: - File Change Row

private struct FileChangeRow: View {
	let file: FileChange
	let isStaged: Bool
	let selectedFileIds: Set<String>
	let onToggle: () -> Void
	let onToggleSelected: () -> Void
	let onDiscard: (() -> Void)?
	let onDelete: (() -> Void)?

	private var statusColor: Color {
		switch file.status {
		case .added,
		     .untracked:
			.green
		case .modified:
			.orange
		case .deleted:
			.red
		case .copied,
		     .renamed:
			.blue
		case .typeChanged:
			.purple
		}
	}

	var body: some View {
		HStack(spacing: 8) {
			// Checkbox
			Button(action: handleToggle) {
				Image(systemName: isStaged ? "checkmark.square.fill" : "square")
					.foregroundStyle(isStaged ? .blue : .secondary)
			}
			.buttonStyle(.plain)

			// Status Icon
			Image(systemName: file.status.iconName)
				.foregroundStyle(statusColor)
				.imageScale(.small)

			// File Info
			VStack(alignment: .leading, spacing: 2) {
				Text(file.fileName)
					.font(.body)
					.lineLimit(1)

				if !file.directoryPath.isEmpty {
					Text(file.directoryPath)
						.font(.caption)
						.foregroundStyle(.secondary)
						.lineLimit(1)
				}
			}

			Spacer()

			// Actions Menu
			Menu {
				if let onDiscard {
					Button("Discard Changes", role: .destructive) {
						onDiscard()
					}
				}

				if let onDelete {
					Button("Delete File", role: .destructive) {
						onDelete()
					}
				}
			} label: {
				Image(systemName: "ellipsis.circle")
					.foregroundStyle(.secondary)
			}
			.buttonStyle(.plain)
			.opacity(onDiscard != nil || onDelete != nil ? 1 : 0)
		}
		.padding(.vertical, 4)
	}

	private func handleToggle() {
		// If multiple files are selected and this file is among them, toggle all selected
		if selectedFileIds.count > 1, selectedFileIds.contains(file.id) {
			onToggleSelected()
		}
		// Otherwise, toggle just this file
		else {
			onToggle()
		}
	}
}

// MARK: - Diff Viewer

private struct DiffViewer: View {
	let diff: FileDiff
	let isStaged: Bool
	let onStageHunk: (DiffHunk) -> Void
	let onUnstageHunk: (DiffHunk) -> Void
	let onDiscardHunk: (DiffHunk) -> Void

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 0) {
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
							onStage: { onStageHunk(hunk) },
							onUnstage: { onUnstageHunk(hunk) },
							onDiscard: { onDiscardHunk(hunk) }
						)
					}
				}
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
}

// MARK: - Hunk View

private struct HunkView: View {
	let hunk: DiffHunk
	let isStaged: Bool
	let onStage: () -> Void
	let onUnstage: () -> Void
	let onDiscard: () -> Void

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			// Hunk Header with Actions
			HStack {
				Text(hunk.header)
					.font(.system(.caption, design: .monospaced))
					.foregroundStyle(.secondary)

				Spacer()

				// Hunk Actions
				HStack(spacing: 6) {
					if !isStaged {
						HunkActionButton(title: "Stage", action: onStage)
					}

					if isStaged {
						HunkActionButton(title: "Unstage", action: onUnstage)
					}

					if !isStaged {
						HunkActionButton(title: "Discard", action: onDiscard)
					}
				}
			}
			.padding(.horizontal, 12)
			.padding(.vertical, 8)
			.background(Color(nsColor: .controlBackgroundColor))

			// Hunk Lines
			ForEach(hunk.lines) { line in
				DiffLineView(line: line)
			}
		}
		.background(Color(nsColor: .textBackgroundColor))
		.cornerRadius(6)
		.overlay(
			RoundedRectangle(cornerRadius: 6)
				.stroke(Color(nsColor: .separatorColor), lineWidth: 1)
		)
		.padding(.horizontal, 12)
		.padding(.vertical, 8)
	}
}

// MARK: - Hunk Action Button

private struct HunkActionButton: View {
	let title: String
	let action: () -> Void

	var body: some View {
		Button(action: action) {
			Text(title)
				.font(.caption)
				.padding(.horizontal, 10)
				.padding(.vertical, 5)
				.background(Color(nsColor: .controlBackgroundColor))
				.foregroundStyle(.primary)
				.cornerRadius(4)
				.overlay(
					RoundedRectangle(cornerRadius: 4)
						.stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
				)
		}
		.buttonStyle(.plain)
	}
}

// MARK: - Section Header

private struct SectionHeader: View {
	let title: String
	let count: Int

	var body: some View {
		HStack {
			Text(title)
				.font(.headline)
				.foregroundStyle(.secondary)
			Spacer()
			Text("\(count)")
				.font(.caption)
				.foregroundStyle(.secondary)
		}
		.padding(.horizontal, 12)
		.padding(.vertical, 8)
		.background(Color(nsColor: .controlBackgroundColor))
	}
}

// MARK: - Empty State View

private struct EmptyStateView: View {
	let title: String
	let systemImage: String
	let description: String

	var body: some View {
		VStack {
			Spacer()
			ContentUnavailableView(
				title,
				systemImage: systemImage,
				description: Text(description)
			)
			Spacer()
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
	}
}

// MARK: - Diff Line View

private struct DiffLineView: View {
	let line: DiffLine

	private var linePrefix: String {
		switch line.type {
		case .addition: "+"
		case .deletion: "-"
		case .context: " "
		}
	}

	private var lineColor: Color {
		switch line.type {
		case .addition: Color(red: 0.0, green: 0.5, blue: 0.0)
		case .deletion: Color(red: 0.7, green: 0.0, blue: 0.0)
		case .context: .secondary
		}
	}

	private var backgroundColor: Color {
		switch line.type {
		case .addition:
			Color(red: 0.85, green: 0.95, blue: 0.85)
		case .deletion:
			Color(red: 0.95, green: 0.85, blue: 0.85)
		case .context:
			Color.clear
		}
	}

	var body: some View {
		HStack(spacing: 0) {
			// Line prefix indicator
			Text(linePrefix)
				.frame(width: 20, alignment: .center)
				.foregroundStyle(lineColor)

			// Line content
			Text(line.content)
				.font(.system(.body, design: .monospaced))
				.foregroundStyle(lineColor)
				.frame(maxWidth: .infinity, alignment: .leading)
		}
		.padding(.vertical, 1)
		.padding(.horizontal, 8)
		.background(backgroundColor)
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
