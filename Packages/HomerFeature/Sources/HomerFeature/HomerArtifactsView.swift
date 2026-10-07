import AppKit
import AppUI
import ComposableArchitecture
import SwiftUI

/// A run's artifacts in a sheet over its page (`artifact-picker-dialog.tsx`): a click saves the
/// file to Downloads.
struct HomerArtifactsView: View {
	let store: StoreOf<HomerArtifactsReducer>

	@Environment(\.dismiss)
	private var dismiss

	var body: some View {
		VStack(spacing: 0) {
			HStack(spacing: 10) {
				VStack(alignment: .leading, spacing: 2) {
					Text("Artifacts of #\(store.processId)")
						.scaledFont(.headline)
					Text("Click a file to save it to Downloads.")
						.scaledFont(.callout)
						.foregroundStyle(.secondary)
				}
				Spacer()
				if store.isLoading {
					ProgressView()
						.controlSize(.small)
				}
				Button {
					store.send(.refreshTapped)
				} label: {
					Label("Refresh", systemImage: "arrow.clockwise")
				}
				.buttonStyle(.scaledBordered)
				.disabled(store.isLoading)
				Button("Done") { dismiss() }
					.buttonStyle(.scaledBorderedProminent)
					.keyboardShortcut(.cancelAction)
			}
			.padding(12)

			Divider()

			content
				.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
		.frame(minWidth: 620, idealWidth: 720, minHeight: 360, idealHeight: 480)
		.task { store.send(.task) }
	}

	@ViewBuilder
	private var content: some View {
		if !store.hasLoaded {
			if let error = store.loadError {
				Text("Failed to load artifacts: \(error)")
					.scaledFont(.callout)
					.foregroundStyle(.red)
					.padding()
			}
			else {
				ProgressView("Loading…")
			}
		}
		else if store.artifacts.isEmpty {
			EmptyStateView(
				title: "No Artifacts Yet",
				systemImage: "doc",
				description: "Files appear here once the agent writes them."
			)
		}
		else {
			VStack(spacing: 0) {
				if let error = store.loadError {
					HomerErrorBanner(message: error)
					Divider()
				}
				Table(store.artifacts) {
					TableColumn("Path") { artifact in
						row(artifact)
					}
					TableColumn("Size") { artifact in
						Text(artifact.size.formatted(.byteCount(style: .file)))
							.scaledFont(.callout)
							.monospacedDigit()
					}
					.width(min: 70, ideal: 90, max: 120)
					TableColumn("Modified") { artifact in
						let date = Date(timeIntervalSince1970: artifact.modified)
						Text(date, format: .relative(presentation: .named))
							.scaledFont(.callout)
							.foregroundStyle(.secondary)
							.help(HomerFormat.timestamp(artifact.modified))
					}
					.width(min: 90, ideal: 120, max: 160)
				}
			}
		}
	}

	private func row(_ artifact: HomerArtifact) -> some View {
		HStack(spacing: 6) {
			Button {
				store.send(.downloadTapped(path: artifact.path))
			} label: {
				Label(artifact.path, systemImage: "doc.text")
					.scaledFont(.callout, design: .monospaced)
					.lineLimit(1)
					.truncationMode(.middle)
			}
			.buttonStyle(.link)
			.help("Save \(artifact.path) to Downloads")
			.disabled(store.downloadingPaths.contains(artifact.path))

			if store.downloadingPaths.contains(artifact.path) {
				ProgressView()
					.controlSize(.mini)
			}
			else if let url = store.savedFiles[artifact.path] {
				Button {
					NSWorkspace.shared.activateFileViewerSelecting([url])
				} label: {
					Image(systemName: "checkmark.circle.fill")
						.foregroundStyle(.green)
				}
				.buttonStyle(.plain)
				.help("Saved as \(url.lastPathComponent) — show in Finder")
			}
			else if let error = store.downloadErrors[artifact.path] {
				Image(systemName: "exclamationmark.triangle.fill")
					.foregroundStyle(.red)
					.help(error)
			}
		}
	}
}
