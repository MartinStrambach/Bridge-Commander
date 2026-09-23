import AppKit
import AppUI
import ComposableArchitecture
import DiffModelMapping
import GitCore
import SwiftUI

struct FileChangeListView: View {
	@Bindable
	var store: StoreOf<FileChangeList>

	@FocusState
	private var isListFocused: Bool

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
							file: file.toAppUI(),
							isStaged: store.listType == .staged,
							onToggle: { store.send(.toggleTapped(file)) }
						)
						.tag(file.id)
						.background(
							ClickCatcher(
								onClick: { isListFocused = true },
								onDoubleClick: {
									store.send(.updateSelection([file.id]))
									store.send(.openInIDE(file))
								}
							)
						)
					}
				}
				// A single list-level context menu driven by the current selection.
				// Per-row `.contextMenu` is intentionally avoided: ⌘A is dispatched through
				// `NSMenu performKeyEquivalent:`, which forces AppKit to build every row's
				// menu, turning select-all into O(rows^2) work and freezing the app.
				.contextMenu(forSelectionType: FileChange.ID.self) { ids in
					contextMenu(forSelection: ids)
				}
				.listStyle(.plain)
				.focused($isListFocused)
				// Clicking a row does not make the list first responder on macOS 27, so focus is
				// claimed explicitly: on a click (see `ClickCatcher`), when the list opens with a
				// file already auto-selected, and whenever the selection changes — which also
				// carries focus across when staging a file moves the selection into the other list.
				.onAppear {
					if !store.selectedFileIds.isEmpty {
						isListFocused = true
					}
				}
				.onChange(of: store.selectedFileIds) { _, ids in
					if !ids.isEmpty {
						isListFocused = true
					}
				}
				// ↑/↓ are handled here rather than left to the native table: on macOS 27 they
				// neither moved the selection nor wrote it back through `selection`. ⇧ is left
				// to the table so extending the selection keeps working.
				.onKeyPress(keys: [.upArrow, .downArrow]) { press in
					guard press.modifiers.isDisjoint(with: [.shift, .command, .option]) else {
						return .ignored
					}

					store.send(.moveSelection(by: press.key == .upArrow ? -1 : 1))
					return .handled
				}
				.onKeyPress(.space) {
					store.send(.spaceKeyPressed)
					return .handled
				}
				.onReturnPress {
					if let file = store.files.first(where: { store.selectedFileIds.contains($0.id) }) {
						store.send(.openInIDE(file))
					}
				}
				.alert($store.scope(\.$alert, action: \.alert))
			}
		}
	}

	// Built lazily by AppKit only when a context menu is actually requested
	// (right-click), so the O(n) filtering here runs once per interaction — never
	// per row and never during ⌘A select-all.
	@ViewBuilder
	private func contextMenu(forSelection ids: Set<FileChange.ID>) -> some View {
		if ids.count > 1 {
			let selectedFiles = store.files.filter { ids.contains($0.id) }

			if store.listType == .staged {
				Button("Unstage All Selected (\(ids.count) files)") {
					store.send(.toggleSelectedTapped)
				}
			}
			else {
				let allTracked = selectedFiles.allSatisfy { $0.status != .untracked }
				let allUntracked = selectedFiles.allSatisfy { $0.status == .untracked }

				Button("Stage All Selected (\(ids.count) files)") {
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
			Button("Reveal in Finder (\(ids.count) files)") {
				openInFinder(selectedFiles)
			}
		}
		else if
			let id = ids.first,
			let file = store.files.first(where: { $0.id == id }) {
			Button("Open in IDE") { store.send(.openInIDE(file)) }
			Button("Reveal in Finder") { openInFinder([file]) }
			Button("Copy File Name") {
				NSPasteboard.general.clearContents()
				NSPasteboard.general.setString(file.fileName, forType: .string)
			}

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

	private func openInFinder(_ files: [FileChange]) {
		let urls = files.map { file in
			URL(fileURLWithPath: store.repositoryPath).appendingPathComponent(file.path)
		}
		NSWorkspace.shared.activateFileViewerSelecting(urls)
	}
}

private struct ClickCatcher: NSViewRepresentable {
	let onClick: () -> Void
	let onDoubleClick: () -> Void

	func makeNSView(context: Context) -> ClickCatcherView {
		ClickCatcherView(onClick: onClick, onDoubleClick: onDoubleClick)
	}

	func updateNSView(_ nsView: ClickCatcherView, context: Context) {
		nsView.onClick = onClick
		nsView.onDoubleClick = onDoubleClick
	}
}

private final class ClickCatcherView: NSView {
	var onClick: (() -> Void)?
	var onDoubleClick: (() -> Void)?

	private var monitor: Any?

	init(onClick: @escaping () -> Void, onDoubleClick: @escaping () -> Void) {
		self.onClick = onClick
		self.onDoubleClick = onDoubleClick
		super.init(frame: .zero)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError()
	}

	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		if let monitor {
			NSEvent.removeMonitor(monitor)
			self.monitor = nil
		}
		guard window != nil else {
			return
		}

		monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
			guard
				let self,
				event.window === self.window,
				bounds.contains(convert(event.locationInWindow, from: nil))
			else {
				return event
			}

			onClick?()
			if event.clickCount == 2 {
				onDoubleClick?()
			}
			return event
		}
	}

}
