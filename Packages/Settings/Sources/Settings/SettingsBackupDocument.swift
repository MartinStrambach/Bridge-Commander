import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// An encoded `SettingsBackup` for the view's `fileExporter`. Importing reads the file through
/// `SettingsBackupClient` instead; reading is here only because `FileDocument` requires it.
public struct SettingsBackupDocument: FileDocument, Equatable, Sendable {
	public static let readableContentTypes: [UTType] = [.json]

	public let data: Data
	/// The name the save panel suggests.
	public let filename: String

	public init(data: Data, filename: String) {
		self.data = data
		self.filename = filename
	}

	public init(configuration: ReadConfiguration) throws {
		data = configuration.file.regularFileContents ?? Data()
		filename = configuration.file.filename ?? ""
	}

	public func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
		FileWrapper(regularFileWithContents: data)
	}
}
