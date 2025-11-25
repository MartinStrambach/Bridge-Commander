import Foundation

// MARK: - Xcode Service

struct XcodeServiceImpl: XcodeServiceType, Sendable {
	func hasXcodeProject(in path: String) -> Bool {
		XcodeProjectDetector.hasXcodeProject(in: path)
	}

	func findXcodeProject(in repositoryPath: String) -> String? {
		XcodeProjectDetector.findXcodeProject(in: repositoryPath)
	}
}
