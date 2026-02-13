import Dependencies
import DependenciesMacros
import Foundation

// MARK: - Xcode Service

@DependencyClient
nonisolated struct XcodeClient: Sendable {
	var hasXcodeProject: @Sendable (_ in: String, _ iosSubfolderPath: String) -> Bool = { _, _ in false }
	var findXcodeProject: @Sendable (_ in: String, _ iosSubfolderPath: String) -> String? = { _, _ in nil }
}

extension XcodeClient: DependencyKey {
	static let liveValue = XcodeClient(
		hasXcodeProject: { path, iosSubfolderPath in
			XcodeProjectDetector.hasXcodeProject(in: path, iosSubfolderPath: iosSubfolderPath)
		},
		findXcodeProject: { repositoryPath, iosSubfolderPath in
			XcodeProjectDetector.findXcodeProject(in: repositoryPath, iosSubfolderPath: iosSubfolderPath)
		}
	)
}

extension XcodeClient: TestDependencyKey {
	static let testValue = XcodeClient()
}
