import AppKit
import AppUI
import SwiftUI
import ToolsIntegration

/// Where Xcode's DerivedData space goes: what still serves a project, what is left behind by
/// projects that are gone, and the caches every project shares. Measured only on request.
struct DerivedDataUsageView: View {
	let usage: DerivedDataUsage?
	let isMeasuring: Bool
	let deletingKind: DerivedDataUsage.Kind?
	let onMeasure: () -> Void
	let onDelete: (DerivedDataUsage.Kind) -> Void

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			if let usage {
				Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
					ForEach(DerivedDataUsage.Kind.allCases, id: \.self) { kind in
						row(Self.title(of: kind), tally: usage[kind]) {
							deleteButton(kind, usage: usage)
						}
					}
					Divider()
						.gridCellUnsizedAxes(.horizontal)
					row(
						"Total",
						tally: .init(folders: usage.totalFolders, bytes: usage.totalBytes)
					)
					.fontWeight(.semibold)
				}
				.scaledFont(.callout)
			}

			HStack(spacing: 8) {
				Button {
					onMeasure()
				} label: {
					Label(usage == nil ? "Measure" : "Measure Again", systemImage: "internaldrive")
				}
				.buttonStyle(.scaledBordered)
				.disabled(isMeasuring || deletingKind != nil)

				Button {
					NSWorkspace.shared.activateFileViewerSelecting([DerivedDataUsageScanner.defaultDerivedDataURL])
				} label: {
					Label("Show in Finder", systemImage: "folder")
				}
				.buttonStyle(.scaledBordered)

				if isMeasuring {
					ProgressView()
						.controlSize(.small)
					if let usage, usage.totalFolders > 0 {
						Text("Measured \(usage.measuredFolders) of \(usage.totalFolders) folders…")
							.scaledFont(.caption)
							.foregroundColor(.secondary)
					}
				}
			}

			Text(
				"Orphaned folders belong to projects that no longer exist, such as worktrees removed outside the app. Leftovers have lost the file naming their project, probably because they were deleted while Xcode still had it open. Deleting any folder is safe, as Xcode recreates what it needs, but clearing the shared caches slows the next builds."
			)
			.scaledFont(.caption)
			.foregroundColor(.secondary)
		}
	}

	/// Sizes grow while a measurement runs; the progress line beside the buttons says it is not done.
	private func row(
		_ title: String,
		tally: DerivedDataUsage.Tally,
		@ViewBuilder accessory: () -> some View = { EmptyView() }
	) -> some View {
		GridRow {
			Text(title)
			Text(tally.folders == 1 ? "1 folder" : "\(tally.folders) folders")
				.foregroundColor(.secondary)
				.gridColumnAlignment(.trailing)
			Text(tally.bytes.formatted(.byteCount(style: .file)))
				.monospacedDigit()
				.gridColumnAlignment(.trailing)
			accessory()
		}
	}

	/// Offered once a measurement is complete, so the confirmation can name the space it frees.
	@ViewBuilder
	private func deleteButton(_ kind: DerivedDataUsage.Kind, usage: DerivedDataUsage) -> some View {
		if deletingKind == kind {
			HStack(spacing: 6) {
				ProgressView()
					.controlSize(.small)
				Text("Deleting…")
					.scaledFont(.caption)
					.foregroundColor(.secondary)
			}
		}
		else if DerivedDataUsageScanner.deletableKinds.contains(kind) {
			Button("Delete…", role: .destructive) {
				onDelete(kind)
			}
			.buttonStyle(.scaledBordered)
			.controlSize(.small)
			.disabled(isMeasuring || !usage.isComplete || deletingKind != nil || usage[kind].folders == 0)
		}
	}

	private static func title(of kind: DerivedDataUsage.Kind) -> String {
		switch kind {
		case .inUse: "In use by existing projects"
		case .orphaned: "Orphaned"
		case .leftover: "Leftovers"
		case .sharedCache: "Shared caches"
		}
	}
}
