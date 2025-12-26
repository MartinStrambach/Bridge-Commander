import Foundation

// MARK: - Xcode Service

struct XcodeServiceImpl: XcodeServiceType, Sendable {
	func hasXcodeProject(in path: String, iosSubfolderPath: String) -> Bool {
		XcodeProjectDetector.hasXcodeProject(in: path, iosSubfolderPath: iosSubfolderPath)
	}

	func findXcodeProject(in repositoryPath: String, iosSubfolderPath: String) -> String? {
		XcodeProjectDetector.findXcodeProject(in: repositoryPath, iosSubfolderPath: iosSubfolderPath)
	}
}
