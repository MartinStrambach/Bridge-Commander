import Dependencies
import DependenciesMacros
import Foundation

/// The disk access settings import needs: reading the file the user picked, and checking which of
/// its repositories exist on this Mac. A dependency so the reducer's import flow is testable
/// without files on disk; writing goes through the view's `fileExporter`.
@DependencyClient
public struct SettingsBackupClient: Sendable {
	public var readFile: @Sendable (_ url: URL) async throws -> Data
	/// Those of `paths` that are not an existing directory.
	public var missingDirectories: @Sendable (_ paths: [String]) async -> [String] = { _ in [] }
}

extension SettingsBackupClient: DependencyKey {
	public static let liveValue = SettingsBackupClient(
		readFile: { url in
			try await onDiskQueue { try Data(contentsOf: url) }
		},
		missingDirectories: { paths in
			await (try? onDiskQueue {
				paths.filter { path in
					var isDirectory: ObjCBool = false
					return !FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
						|| !isDirectory.boolValue
				}
			}) ?? []
		}
	)
}

extension SettingsBackupClient: TestDependencyKey {
	public static let testValue = SettingsBackupClient()
}

/// Runs blocking file access off the cooperative pool: a file on a network volume or an iCloud
/// placeholder can take a while to read, and would hold a pool thread for all of it.
private func onDiskQueue<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
	try await withCheckedThrowingContinuation { continuation in
		DispatchQueue.global(qos: .userInitiated).async {
			continuation.resume(with: Result { try work() })
		}
	}
}
