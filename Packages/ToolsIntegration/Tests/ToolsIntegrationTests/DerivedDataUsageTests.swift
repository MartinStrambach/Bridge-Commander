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
		#expect(last.folders.count == 4)
		#expect(last.folders.values.allSatisfy { $0.bytes != nil })
		#expect(last.folders["ModuleCache.noindex"]?.bytes == last[.sharedCache].bytes)
	}

	@Test("deleted folders are subtracted with the kind and size they were measured with")
	func removesDeletedFolders() {
		var usage = DerivedDataUsage(
			tallies: [.inUse: .init(folders: 1, bytes: 4096), .orphaned: .init(folders: 2, bytes: 3072)],
			measuredFolders: 3,
			totalFolders: 3,
			folders: [
				"A": .init(kind: .inUse, bytes: 4096),
				"B": .init(kind: .orphaned, bytes: 1024),
				"C": .init(kind: .orphaned, bytes: 2048),
			]
		)

		usage.removeFolders(named: ["B", "NotMeasured"])

		#expect(usage[.orphaned] == .init(folders: 1, bytes: 2048))
		#expect(usage[.inUse] == .init(folders: 1, bytes: 4096))
		#expect(usage.totalFolders == 2)
		#expect(usage.isComplete)
		#expect(usage.folders.keys.sorted() == ["A", "C"])
	}

	@Test("deleting a kind removes exactly its folders and nothing else")
	func deletesOnlyTheRequestedKind() async throws {
		let root = FileManager.default.temporaryDirectory
			.appending(path: "DerivedDataUsageTests-\(UUID().uuidString)", directoryHint: .isDirectory)
		defer { try? FileManager.default.removeItem(at: root) }
		let derivedData = root.appending(path: "DerivedData", directoryHint: .isDirectory)
		let workspace = root.appending(path: "App.xcodeproj", directoryHint: .isDirectory)
		try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)

		try makeProjectFolder("App-aaaaaaaaaaaaaaaaaaaaaaaaaaaa", workspacePath: workspace.path, in: derivedData)
		try makeProjectFolder("Gone-bbbbbbbbbbbbbbbbbbbbbbbbbbbb", workspacePath: root.path + "/Gone.xcodeproj", in: derivedData)
		try makeProjectFolder("Gone-dddddddddddddddddddddddddddd", workspacePath: root.path + "/Old.xcworkspace", in: derivedData)
		try makeFolder("Gone-bbbbbbbbbbbbbbbbbbbbbbbbbbbb/Build/Products/Debug", in: derivedData)
		try Data(count: 1024).write(to: derivedData.appending(path: "Gone-bbbbbbbbbbbbbbbbbbbbbbbbbbbb/Build/Products/Debug/App"))
		try Data(count: 1024).write(to: derivedData.appending(path: "Gone-bbbbbbbbbbbbbbbbbbbbbbbbbbbb/Build/build.db"))
		try makeFolder("Left-cccccccccccccccccccccccccccc/Logs", in: derivedData)
		try makeFolder("ModuleCache.noindex", in: derivedData)

		let deletion = await DerivedDataUsageScanner.deleteFolders(of: .orphaned, in: derivedData)

		#expect(deletion == DerivedDataDeletion(deletedFolders: ["Gone-bbbbbbbbbbbbbbbbbbbbbbbbbbbb", "Gone-dddddddddddddddddddddddddddd"]))
		let remaining = try FileManager.default.contentsOfDirectory(atPath: derivedData.path).sorted()
		#expect(remaining == ["App-aaaaaaaaaaaaaaaaaaaaaaaaaaaa", "Left-cccccccccccccccccccccccccccc", "ModuleCache.noindex"])

		#expect(await DerivedDataUsageScanner.deleteFolders(of: .leftover, in: derivedData).deletedFolders == ["Left-cccccccccccccccccccccccccccc"])
	}

	@Test("folders in use and shared caches are never deleted", arguments: [DerivedDataUsage.Kind.inUse, .sharedCache])
	func refusesUndeletableKinds(kind: DerivedDataUsage.Kind) async throws {
		let derivedData = FileManager.default.temporaryDirectory
			.appending(path: "DerivedDataUsageTests-\(UUID().uuidString)", directoryHint: .isDirectory)
		defer { try? FileManager.default.removeItem(at: derivedData) }
		try makeFolder("ModuleCache.noindex", in: derivedData)
		try makeProjectFolder("App-aaaaaaaaaaaaaaaaaaaaaaaaaaaa", workspacePath: derivedData.path, in: derivedData)

		#expect(await DerivedDataUsageScanner.deleteFolders(of: kind, in: derivedData) == DerivedDataDeletion())
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

	@Test("nested folders are counted and symbolic links are not followed")
	func sizesNestedFoldersWithoutFollowingLinks() throws {
		let root = FileManager.default.temporaryDirectory
			.appending(path: "DerivedDataUsageTests-\(UUID().uuidString)", directoryHint: .isDirectory)
		defer { try? FileManager.default.removeItem(at: root) }
		let folder = root.appending(path: "Folder", directoryHint: .isDirectory)
		try makeFolder("Folder/a/b/c", in: root)
		try Data(count: 128 * 1024).write(to: folder.appending(path: "a/b/c/deep"))
		let outside = root.appending(path: "outside")
		try Data(count: 1024 * 1024).write(to: outside)
		try FileManager.default.createSymbolicLink(at: folder.appending(path: "a/link"), withDestinationURL: outside)

		let bytes = DerivedDataUsageScanner.allocatedBytes(at: folder)

		#expect(bytes >= 128 * 1024)
		#expect(bytes < 1024 * 1024)
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
