import Dependencies
import DependenciesMacros
import Foundation

// MARK: - Xcode Service

@DependencyClient
public struct XcodeClient: Sendable {
	public var hasXcodeProject: @Sendable (_ in: String, _ iosSubfolderPath: String) -> Bool = { _, _ in false }
	public var findXcodeProject: @Sendable (_ in: String, _ iosSubfolderPath: String, _ preference: XcodeFilePreference) -> String? = { _, _, _ in nil }
	/// The generator whose manifest the iOS subfolder holds; see `XcodeProjectDetector.projectGenerator`.
	public var projectGenerator: @Sendable (_ in: String, _ iosSubfolderPath: String) -> ProjectGenerator? = { _, _ in nil }
	/// Runs tuist install & generate, or xcodegen generate; see `XcodeProjectGenerator.generateProject`.
	public var generateProject: @Sendable (
		_ at: String,
		_ iosSubfolderPath: String,
		_ generator: ProjectGenerator,
		_ shouldOpenXcode: Bool,
		_ misePath: String,
		_ runMode: GeneratorRunMode,
		_ onStateChange: @Sendable (XcodeProjectState) async -> Void
	) async throws -> String
	public var openProject: @Sendable (_ at: String) async throws -> Void
}

extension XcodeClient: DependencyKey {
	public static let liveValue = XcodeClient(
		hasXcodeProject: { path, iosSubfolderPath in
			XcodeProjectDetector.hasXcodeProject(in: path, iosSubfolderPath: iosSubfolderPath)
		},
		findXcodeProject: { repositoryPath, iosSubfolderPath, preference in
			XcodeProjectDetector.findXcodeProject(in: repositoryPath, iosSubfolderPath: iosSubfolderPath, preference: preference)
		},
		projectGenerator: { repositoryPath, iosSubfolderPath in
			XcodeProjectDetector.projectGenerator(in: repositoryPath, iosSubfolderPath: iosSubfolderPath)
		},
		generateProject: { repositoryPath, iosSubfolderPath, generator, shouldOpenXcode, misePath, runMode, onStateChange in
			try await XcodeProjectGenerator.generateProject(
				at: repositoryPath,
				iosSubfolderPath: iosSubfolderPath,
				generator: generator,
				shouldOpenXcode: shouldOpenXcode,
				misePath: misePath,
				runMode: runMode,
				onStateChange: onStateChange
			)
		},
		openProject: { projectPath in
			try await XcodeProjectGenerator.openProject(at: projectPath)
		}
	)
}

extension XcodeClient: TestDependencyKey {
	public static let testValue = XcodeClient()
}
