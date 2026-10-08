import ActivityLog
import AppKit
import AppUI
import SwiftUI
import UniformTypeIdentifiers

/// The activity log's size and its Save, Show in Finder and Clear buttons. The log is a file the
/// app appends to from every package, not state a reducer holds, so these act on
/// `ActivityLog.shared` directly.
struct ActivityLogControls: View {
	@State
	private var size: UInt64 = 0

	/// The log as it was when Save was clicked; non-nil while the save panel is up.
	@State
	private var exportedLog: ActivityLogDocument?

	@State
	private var isConfirmingClear = false

	@State
	private var saveFailure: String?

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("Size on disk: \(size.formatted(.byteCount(style: .file)))")
				.scaledFont(.callout)
				.foregroundColor(.secondary)

			HStack(spacing: 8) {
				Button {
					Task {
						exportedLog = ActivityLogDocument(data: await ActivityLog.shared.exportData())
					}
				} label: {
					Label("Save Log…", systemImage: "square.and.arrow.down")
				}
				.buttonStyle(.scaledBordered)

				Button {
					NSWorkspace.shared.activateFileViewerSelecting([ActivityLog.shared.fileURL])
				} label: {
					Label("Show in Finder", systemImage: "folder")
				}
				.buttonStyle(.scaledBordered)
				.disabled(!FileManager.default.fileExists(atPath: ActivityLog.shared.fileURL.path))

				Button(role: .destructive) {
					isConfirmingClear = true
				} label: {
					Label("Clear Log…", systemImage: "trash")
				}
				.buttonStyle(.scaledBordered)
				.disabled(size == 0)
			}
		}
		.fileExporter(
			isPresented: Binding(
				get: { exportedLog != nil },
				set: { if !$0 { exportedLog = nil } }
			),
			document: exportedLog,
			contentType: .log,
			defaultFilename: "Bridge Commander Activity \(Date.now.formatted(.iso8601.year().month().day())).log"
		) { result in
			if case let .failure(error) = result {
				saveFailure = error.localizedDescription
			}
		}
		.confirmationDialog("Clear the activity log?", isPresented: $isConfirmingClear) {
			Button("Clear Log", role: .destructive) {
				Task {
					await ActivityLog.shared.clear()
					size = await ActivityLog.shared.size()
				}
			}
		} message: {
			Text("Everything recorded so far is deleted. Save the log first to keep a copy.")
		}
		.alert(
			"The log could not be saved",
			isPresented: Binding(
				get: { saveFailure != nil },
				set: { if !$0 { saveFailure = nil } }
			)
		) {
			Button("OK") {}
		} message: {
			Text(saveFailure ?? "")
		}
		.task {
			size = await ActivityLog.shared.size()
		}
	}
}

/// The exported log, for `fileExporter`. Only ever written; reading is required by `FileDocument`.
private struct ActivityLogDocument: FileDocument {
	static let readableContentTypes: [UTType] = [.log, .plainText]

	let data: Data

	init(data: Data) {
		self.data = data
	}

	init(configuration: ReadConfiguration) throws {
		data = configuration.file.regularFileContents ?? Data()
	}

	func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
		FileWrapper(regularFileWithContents: data)
	}
}
