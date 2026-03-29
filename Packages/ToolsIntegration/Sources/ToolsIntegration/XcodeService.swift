import Dependencies
import DependenciesMacros
import Foundation

// MARK: - Xcode Service

@DependencyClient
public struct XcodeClient: Sendable {
	public var hasXcodeProject: @Sendable (_ in: String, _ iosSubfolderPath: String) -> Bool = { _, _ in false }
	public var findXcodeProject: @Sendable (_ in: String, _ iosSubfolderPath: String) -> String? = { _, _ in nil }
}

extension XcodeClient: DependencyKey {
	public static let liveValue = XcodeClient(
		hasXcodeProject: { path, iosSubfolderPath in
			XcodeProjectDetector.hasXcodeProject(in: path, iosSubfolderPath: iosSubfolderPath)
		},
		findXcodeProject: { repositoryPath, iosSubfolderPath in
			XcodeProjectDetector.findXcodeProject(in: repositoryPath, iosSubfolderPath: iosSubfolderPath)
		}
	)
}

extension XcodeClient: TestDependencyKey {
	public static let testValue = XcodeClient()
}
