import Foundation
import Testing
@testable import ToolsIntegration

@Suite("Xcode DerivedData usage")
struct DerivedDataUsageTests {

	// MARK: - Folder names

	@Test(
		"project folder names end in a dash and 28 lowercase letters",
		arguments: [
			"Tankuj-amjazlzrzzgrvggcxwbbjbcairmc",
			"Unsaved_Xcode_Document_2-apfuumulhsvfbpgegtqwyvmzjpsm",
			"my-app-ceuntrhouzvfdwejysxhiayteyfn",
		]
	)
	func recognizesProjectFolderNames(name: String) {
		#expect(DerivedDataUsageScanner.isProjectFolderName(name))
	}

	@Test(
		"shared cache and malformed names are not project folders",
		arguments: [
			"ModuleCache.noindex",
			"CompilationCache.noindex",
			"SDKExplicitPrecompiledModules",
			"tankuj-simplify-ios",
			"-amjazlzrzzgrvggcxwbbjbcairmc",
			"Tankuj-AMJAZLZRZZGRVGGCXWBBJBCAIRMC",
			"Tankuj-amjazlzrzzgrvggcxwbbjbcairm",
		]
	)
	func rejectsOtherNames(name: String) {
		#expect(!DerivedDataUsageScanner.isProjectFolderName(name))
	}

	// MARK: - Classification

	@Test("a workspace that exists is in use, one that is gone is orphaned")
	func classifiesByWorkspaceExistence() {
		let name = "App-amjazlzrzzgrvggcxwbbjbcairmc"
		#expect(DerivedDataUsageScanner.kind(folderName: name, workspacePath: "/w/App.xcodeproj", workspaceExists: true) == .inUse)
		#expect(DerivedDataUsageScanner.kind(folderName: name, workspacePath: "/w/App.xcodeproj", workspaceExists: false) == .orphaned)
	}

	@Test("without a workspace path, project folders are leftovers and the rest shared caches")
	func classifiesFoldersWithoutWorkspace() {
		#expect(DerivedDataUsageScanner.kind(
			folderName: "App-amjazlzrzzgrvggcxwbbjbcairmc",
			workspacePath: nil,
			workspaceExists: false
		) == .leftover)
		#expect(DerivedDataUsageScanner.kind(
			folderName: "ModuleCache.noindex",
			workspacePath: nil,
			workspaceExists: false
		) == .sharedCache)
	}

	// MARK: - Scanning a folder

	@Test("measuring a DerivedData folder tallies every kind and finishes complete")
	func measuresAllKinds() async throws {
		let root = FileManager.default.temporaryDirectory
			.appending(path: "DerivedDataUsageTests-\(UUID().uuidString)", directoryHint: .isDirectory)
		defer { try? FileManager.default.removeItem(at: root) }
		let derivedData = root.appending(path: "DerivedData", directoryHint: .isDirectory)
		let workspace = root.appending(path: "App.xcodeproj", directoryHint: .isDirectory)
		try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)

		try makeProjectFolder("App-aaaaaaaaaaaaaaaaaaaaaaaaaaaa", workspacePath: workspace.path, in: derivedData)
		try makeProjectFolder("Gone-bbbbbbbbbbbbbbbbbbbbbbbbbbbb", workspacePath: root.path + "/Gone.xcodeproj", in: derivedData)
		try makeFolder("Left-cccccccccccccccccccccccccccc/Logs", in: derivedData)
		try makeFolder("ModuleCache.noindex", in: derivedData)
		try Data(count: 64 * 1024).write(to: derivedData.appending(path: "ModuleCache.noindex/module.pcm"))

		var last = DerivedDataUsage()
		for await usage in DerivedDataUsageScanner.measure(in: derivedData) {
			last = usage
		}

		#expect(last.isComplete)
		#expect(last.totalFolders == 4)
		for kind in DerivedDataUsage.Kind.allCases {
			#expect(last[kind].folders == 1)
		}
		#expect(last[.sharedCache].bytes >= 64 * 1024)
	}

	@Test("deleting a kind removes exactly its folders and nothing else")
	func deletesOnlyTheRequestedKind() throws {
		let root = FileManager.default.temporaryDirectory
			.appending(path: "DerivedDataUsageTests-\(UUID().uuidString)", directoryHint: .isDirectory)
		defer { try? FileManager.default.removeItem(at: root) }
		let derivedData = root.appending(path: "DerivedData", directoryHint: .isDirectory)
		let workspace = root.appending(path: "App.xcodeproj", directoryHint: .isDirectory)
		try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)

		try makeProjectFolder("App-aaaaaaaaaaaaaaaaaaaaaaaaaaaa", workspacePath: workspace.path, in: derivedData)
		try makeProjectFolder("Gone-bbbbbbbbbbbbbbbbbbbbbbbbbbbb", workspacePath: root.path + "/Gone.xcodeproj", in: derivedData)
		try makeProjectFolder("Gone-dddddddddddddddddddddddddddd", workspacePath: root.path + "/Old.xcworkspace", in: derivedData)
		try makeFolder("Left-cccccccccccccccccccccccccccc/Logs", in: derivedData)
		try makeFolder("ModuleCache.noindex", in: derivedData)

		let deletion = DerivedDataUsageScanner.deleteFolders(of: .orphaned, in: derivedData)

		#expect(deletion == DerivedDataDeletion(deletedFolders: 2))
		let remaining = try FileManager.default.contentsOfDirectory(atPath: derivedData.path).sorted()
		#expect(remaining == ["App-aaaaaaaaaaaaaaaaaaaaaaaaaaaa", "Left-cccccccccccccccccccccccccccc", "ModuleCache.noindex"])

		#expect(DerivedDataUsageScanner.deleteFolders(of: .leftover, in: derivedData).deletedFolders == 1)
	}

	@Test("folders in use and shared caches are never deleted", arguments: [DerivedDataUsage.Kind.inUse, .sharedCache])
	func refusesUndeletableKinds(kind: DerivedDataUsage.Kind) throws {
		let derivedData = FileManager.default.temporaryDirectory
			.appending(path: "DerivedDataUsageTests-\(UUID().uuidString)", directoryHint: .isDirectory)
		defer { try? FileManager.default.removeItem(at: derivedData) }
		try makeFolder("ModuleCache.noindex", in: derivedData)
		try makeProjectFolder("App-aaaaaaaaaaaaaaaaaaaaaaaaaaaa", workspacePath: derivedData.path, in: derivedData)

		#expect(DerivedDataUsageScanner.deleteFolders(of: kind, in: derivedData) == DerivedDataDeletion())
		#expect(try FileManager.default.contentsOfDirectory(atPath: derivedData.path).count == 2)
	}

	@Test("a hard-linked file is counted once")
	func countsHardLinksOnce() throws {
		let folder = FileManager.default.temporaryDirectory
			.appending(path: "DerivedDataUsageTests-\(UUID().uuidString)", directoryHint: .isDirectory)
		defer { try? FileManager.default.removeItem(at: folder) }
		try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		let original = folder.appending(path: "original")
		try Data(count: 256 * 1024).write(to: original)
		let single = DerivedDataUsageScanner.allocatedBytes(at: folder)

		try FileManager.default.linkItem(at: original, to: folder.appending(path: "link"))

		#expect(single >= 256 * 1024)
		#expect(DerivedDataUsageScanner.allocatedBytes(at: folder) == single)
	}

	private func makeFolder(_ relativePath: String, in root: URL) throws {
		try FileManager.default.createDirectory(
			at: root.appending(path: relativePath, directoryHint: .isDirectory),
			withIntermediateDirectories: true
		)
	}

	private func makeProjectFolder(_ name: String, workspacePath: String, in root: URL) throws {
		try makeFolder(name, in: root)
		let plist = try PropertyListSerialization.data(
			fromPropertyList: ["WorkspacePath": workspacePath],
			format: .xml,
			options: 0
		)
		try plist.write(to: root.appending(path: "\(name)/info.plist"))
	}
}
