import Dependencies
import DependenciesMacros
import Foundation

// MARK: - Xcode Service

@DependencyClient
public struct XcodeClient: Sendable {
	public var hasXcodeProject: @Sendable (_ in: String, _ iosSubfolderPath: String) -> Bool = { _, _ in false }
	public var findXcodeProject: @Sendable (_ in: String, _ iosSubfolderPath: String, _ preference: XcodeFilePreference) -> String? = { _, _, _ in nil }
	/// Runs tuist install & generate; see `XcodeProjectGenerator.generateProject`.
	public var generateProject: @Sendable (
		_ at: String,
		_ iosSubfolderPath: String,
		_ shouldOpenXcode: Bool,
		_ misePath: String,
		_ runMode: TuistRunMode,
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
		generateProject: { repositoryPath, iosSubfolderPath, shouldOpenXcode, misePath, runMode, onStateChange in
			try await XcodeProjectGenerator.generateProject(
				at: repositoryPath,
				iosSubfolderPath: iosSubfolderPath,
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
