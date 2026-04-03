import AppKit
import AppUI
import ComposableArchitecture
import GitCore
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
							file: file.toAppUI(),
							isStaged: store.listType == .staged,
							selectedFileIds: store.selectedFileIds,
							onToggle: { store.send(.delegate(.toggleAll([file]))) },
							onToggleSelected: { store.send(.toggleSelectedTapped) }
						)
						.tag(file.id)
						.contextMenu { contextMenu(for: file) }
						.background(
							DoubleClickCatcher {
								store.send(.updateSelection([file.id]))
								store.send(.openInIDE(file))
							}
						)
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
			Button("Reveal in Finder (\(store.selectedFileIds.count) files)") {
				let selected = store.files.filter { store.selectedFileIds.contains($0.id) }
				openInFinder(selected)
			}
		}
		else {
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

private struct DoubleClickCatcher: NSViewRepresentable {
	let action: () -> Void

	func makeNSView(context: Context) -> DoubleClickCatcherView {
		DoubleClickCatcherView(action: action)
	}

	func updateNSView(_ nsView: DoubleClickCatcherView, context: Context) {
		nsView.action = action
	}
}

private final class DoubleClickCatcherView: NSView {
	var action: (() -> Void)?

	private var monitor: Any?

	init(action: @escaping () -> Void) {
		self.action = action
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
				event.clickCount == 2,
				event.window === self.window
			else {
				return event
			}

			let point = convert(event.locationInWindow, from: nil)
			if bounds.contains(point) {
				action?()
			}
			return event
		}
	}

}
