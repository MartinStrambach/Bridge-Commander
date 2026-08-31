import Foundation
import Testing
@testable import ToolsIntegration

@Suite("Xcode DerivedData removal")
struct XcodeDerivedDataHelperTests {
	private let worktreePath = "/Users/test/worktrees/feature"

	// MARK: - Workspace path matching

	@Test(
		"workspaces at or inside the worktree match",
		arguments: [
			"/Users/test/worktrees/feature",
			"/Users/test/worktrees/feature/App.xcodeproj",
			"/Users/test/worktrees/feature/Nested/App.xcworkspace",
		]
	)
	func matchesWorkspacesInsideWorktree(workspacePath: String) {
		#expect(XcodeDerivedDataHelper.isWorkspacePath(workspacePath, inWorktreeAt: worktreePath))
	}

	@Test(
		"workspaces outside the worktree do not match, including prefix-sharing siblings",
		arguments: [
			"/Users/test/worktrees/feature-2/App.xcodeproj",
			"/Users/test/worktrees/featureUI/App.xcodeproj",
			"/Users/test/worktrees/other/App.xcodeproj",
			"/Users/test/worktrees",
		]
	)
	func rejectsWorkspacesOutsideWorktree(workspacePath: String) {
		#expect(!XcodeDerivedDataHelper.isWorkspacePath(workspacePath, inWorktreeAt: worktreePath))
	}

	@Test("a trailing slash on the worktree path does not change matching")
	func trailingSlashOnWorktreePath() {
		#expect(XcodeDerivedDataHelper.isWorkspacePath(
			"/Users/test/worktrees/feature/App.xcodeproj",
			inWorktreeAt: worktreePath + "/"
		))
		#expect(!XcodeDerivedDataHelper.isWorkspacePath(
			"/Users/test/worktrees/feature-2/App.xcodeproj",
			inWorktreeAt: worktreePath + "/"
		))
	}

	@Test("empty and root worktree paths never match", arguments: ["", "/", "//"])
	func rejectsDegenerateWorktreePaths(worktreePath: String) {
		#expect(!XcodeDerivedDataHelper.isWorkspacePath(
			"/Users/test/worktrees/feature/App.xcodeproj",
			inWorktreeAt: worktreePath
		))
	}

	// MARK: - Deletion

	@Test("deletes only the folders whose workspace lives in the worktree")
	func deletesMatchingFoldersOnly() throws {
		let derivedData = try makeDerivedDataDirectory()
		defer { try? FileManager.default.removeItem(at: derivedData) }

		let matching = try addFolder(
			named: "App-abcdef",
			workspacePath: "\(worktreePath)/App.xcodeproj",
			in: derivedData
		)
		let sibling = try addFolder(
			named: "App-ghijkl",
			workspacePath: "/Users/test/worktrees/feature-2/App.xcodeproj",
			in: derivedData
		)
		let unrelated = try addFolder(
			named: "Other-mnopqr",
			workspacePath: "/Users/test/other/Other.xcworkspace",
			in: derivedData
		)

		try XcodeDerivedDataHelper.deleteDerivedData(forWorktreePath: worktreePath, in: derivedData)

		#expect(!FileManager.default.fileExists(atPath: matching.path))
		#expect(FileManager.default.fileExists(atPath: sibling.path))
		#expect(FileManager.default.fileExists(atPath: unrelated.path))
	}

	@Test("deletes every folder pointing into the worktree, not just the first")
	func deletesAllMatchingFolders() throws {
		let derivedData = try makeDerivedDataDirectory()
		defer { try? FileManager.default.removeItem(at: derivedData) }

		let first = try addFolder(
			named: "App-abcdef",
			workspacePath: "\(worktreePath)/App.xcodeproj",
			in: derivedData
		)
		let second = try addFolder(
			named: "App-ghijkl",
			workspacePath: "\(worktreePath)/Nested/App.xcworkspace",
			in: derivedData
		)

		try XcodeDerivedDataHelper.deleteDerivedData(forWorktreePath: worktreePath, in: derivedData)

		#expect(!FileManager.default.fileExists(atPath: first.path))
		#expect(!FileManager.default.fileExists(atPath: second.path))
	}

	@Test("keeps folders without an info.plist")
	func keepsFoldersWithoutInfoPlist() throws {
		let derivedData = try makeDerivedDataDirectory()
		defer { try? FileManager.default.removeItem(at: derivedData) }

		let noPlist = try addFolder(named: "ModuleCache.noindex", workspacePath: nil, in: derivedData)

		try XcodeDerivedDataHelper.deleteDerivedData(forWorktreePath: worktreePath, in: derivedData)

		#expect(FileManager.default.fileExists(atPath: noPlist.path))
	}

	@Test("keeps folders whose info.plist has no WorkspacePath")
	func keepsFoldersWithoutWorkspacePathKey() throws {
		let derivedData = try makeDerivedDataDirectory()
		defer { try? FileManager.default.removeItem(at: derivedData) }

		let folder = try addFolder(named: "App-abcdef", workspacePath: nil, in: derivedData)
		let plist = try PropertyListSerialization.data(
			fromPropertyList: ["LastAccessedDate": Date()],
			format: .xml,
			options: 0
		)
		try plist.write(to: folder.appending(path: "info.plist", directoryHint: .notDirectory))

		try XcodeDerivedDataHelper.deleteDerivedData(forWorktreePath: worktreePath, in: derivedData)

		#expect(FileManager.default.fileExists(atPath: folder.path))
	}

	@Test("keeps folders whose info.plist is not a valid plist")
	func keepsFoldersWithMalformedInfoPlist() throws {
		let derivedData = try makeDerivedDataDirectory()
		defer { try? FileManager.default.removeItem(at: derivedData) }

		let folder = try addFolder(named: "App-abcdef", workspacePath: nil, in: derivedData)
		try Data("not a plist".utf8).write(
			to: folder.appending(path: "info.plist", directoryHint: .notDirectory)
		)

		try XcodeDerivedDataHelper.deleteDerivedData(forWorktreePath: worktreePath, in: derivedData)

		#expect(FileManager.default.fileExists(atPath: folder.path))
	}

	@Test("a missing DerivedData directory is not an error")
	func missingDerivedDataDirectory() throws {
		let missing = FileManager.default.temporaryDirectory
			.appending(path: "DerivedData-missing-\(UUID().uuidString)", directoryHint: .isDirectory)

		try XcodeDerivedDataHelper.deleteDerivedData(forWorktreePath: worktreePath, in: missing)
	}

	// MARK: - Fixtures

	private func makeDerivedDataDirectory() throws -> URL {
		let url = FileManager.default.temporaryDirectory
			.appending(path: "DerivedDataTests-\(UUID().uuidString)", directoryHint: .isDirectory)
		try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
		return url
	}

	private func addFolder(named name: String, workspacePath: String?, in derivedData: URL) throws -> URL {
		let folder = derivedData.appending(path: name, directoryHint: .isDirectory)
		try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		if let workspacePath {
			let plist = try PropertyListSerialization.data(
				fromPropertyList: ["WorkspacePath": workspacePath],
				format: .xml,
				options: 0
			)
			try plist.write(to: folder.appending(path: "info.plist", directoryHint: .notDirectory))
		}
		return folder
	}
}
