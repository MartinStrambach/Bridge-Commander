import Foundation
import Testing
@testable import ToolsIntegration

@Suite("XcodeGen command building")
struct XcodeGenCommandHelperTests {
	private let misePath = "/Users/test/.local/bin/mise"

	@Test(
		"each action maps to its xcodegen subcommand",
		arguments: [
			(XcodeGenAction.generate, "generate"),
			(.generateUsingCache, "generate --use-cache"),
			(.dumpSummary, "dump --type summary"),
		]
	)
	func commandStrings(action: XcodeGenAction, expected: String) {
		#expect(action.commandString == expected)
	}

	@Test("a command runs through mise when the run mode is mise")
	func viaMise() {
		#expect(
			XcodeGenCommandHelper.shellCommand(for: .generate, misePath: misePath, runMode: .mise)
				== "\(misePath) exec -- xcodegen generate"
		)
	}

	@Test("a command runs xcodegen directly when the run mode is native")
	func viaNative() {
		#expect(
			XcodeGenCommandHelper.shellCommand(for: .generateUsingCache, misePath: misePath, runMode: .native)
				== "xcodegen generate --use-cache"
		)
	}

	@Test("only the generate commands write the project")
	func generatesProject() {
		#expect(XcodeGenAction.generate.generatesProject)
		#expect(XcodeGenAction.generateUsingCache.generatesProject)
		#expect(!XcodeGenAction.dumpSummary.generatesProject)
	}
}

@Suite("Project generator detection")
struct ProjectGeneratorDetectionTests {
	private func withRepository(_ files: [String], _ body: (String) throws -> Void) throws {
		let root = FileManager.default.temporaryDirectory
			.appendingPathComponent("ProjectGeneratorDetection-\(UUID().uuidString)")
		let iosFolder = root.appendingPathComponent("ios")
		try FileManager.default.createDirectory(at: iosFolder, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: root) }
		for file in files {
			try Data().write(to: iosFolder.appendingPathComponent(file))
		}
		try body(root.path)
	}

	@Test("a project.yml makes the folder an XcodeGen project")
	func xcodeGenYAML() throws {
		try withRepository(["project.yml"]) { path in
			#expect(XcodeProjectDetector.projectGenerator(in: path, iosSubfolderPath: "ios") == .xcodeGen)
			#expect(XcodeProjectDetector.xcodeGenSpecPath(in: path, iosSubfolderPath: "ios")?.hasSuffix("ios/project.yml") == true)
		}
	}

	@Test("a project.json spec is found when there is no project.yml")
	func xcodeGenJSON() throws {
		try withRepository(["project.json"]) { path in
			#expect(XcodeProjectDetector.projectGenerator(in: path, iosSubfolderPath: "ios") == .xcodeGen)
			#expect(XcodeProjectDetector.xcodeGenSpecPath(in: path, iosSubfolderPath: "ios")?.hasSuffix("ios/project.json") == true)
		}
	}

	@Test("Tuist wins when the folder holds both manifests")
	func tuistWins() throws {
		try withRepository(["project.yml", "Project.swift"]) { path in
			#expect(XcodeProjectDetector.projectGenerator(in: path, iosSubfolderPath: "ios") == .tuist)
		}
	}

	@Test("a folder with neither manifest has no generator")
	func noGenerator() throws {
		try withRepository(["README.md"]) { path in
			#expect(XcodeProjectDetector.projectGenerator(in: path, iosSubfolderPath: "ios") == nil)
			#expect(XcodeProjectDetector.xcodeGenSpecPath(in: path, iosSubfolderPath: "ios") == nil)
		}
	}
}
