import ComposableArchitecture
import GitCore
@testable import RepositoryFeature

extension TestStore where State == RepositoryListReducer.State, Action == RepositoryListReducer.Action {
	/// Delivers a scan of `rootPath`, tracking it first as adding the repository does. A scan builds
	/// a group only for a tracked repository — one landing after Clear or a removal must not bring
	/// its group back — so a group seeded through `didScanGroup` alone never appears.
	@discardableResult
	func sendScan(
		rootPath: String,
		rows: [ScannedRepository],
		fileID: StaticString = #fileID,
		filePath: StaticString = #filePath,
		line: UInt = #line,
		column: UInt = #column
	) async -> TestStoreTask {
		state.$trackedRepoPaths.withLock { paths in
			if !paths.contains(rootPath) {
				paths.append(rootPath)
			}
		}
		return await send(
			.didScanGroup(rootPath: rootPath, rows: rows),
			fileID: fileID,
			file: filePath,
			line: line,
			column: column
		)
	}
}
