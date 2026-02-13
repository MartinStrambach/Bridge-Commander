import Foundation

nonisolated enum XcodeProjectDetector {

	/// Finds an Xcode workspace or project in the configured iOS subfolder
	/// - Parameters:
	///   - repositoryPath: The repository root path
	///   - iosSubfolderPath: The iOS subfolder path (e.g., "ios/FlashScore")
	/// - Returns: Path to .xcworkspace or .xcodeproj, or nil if not found
	/// - Note: Prioritizes .xcworkspace over .xcodeproj
	static func findXcodeProject(in repositoryPath: String, iosSubfolderPath: String) -> String? {
		let fileManager = FileManager.default

		// Build path to iOS subfolder
		let iosFlashscorePath = Self.getIosFlashscorePath(in: repositoryPath, iosSubfolderPath: iosSubfolderPath)

		// Check if ios/Flashscore directory exists
		var isDirectory: ObjCBool = false
		guard
			fileManager.fileExists(atPath: iosFlashscorePath, isDirectory: &isDirectory),
			isDirectory.boolValue
		else {
			return nil
		}

		// Get directory contents
		guard let contents = try? fileManager.contentsOfDirectory(atPath: iosFlashscorePath) else {
			return nil
		}

		// Priority 1: Look for .xcworkspace
		if let workspace = contents.first(where: { $0.hasSuffix(".xcworkspace") }) {
			return (iosFlashscorePath as NSString).appendingPathComponent(workspace)
		}

		// Priority 2: Look for .xcodeproj
		if let project = contents.first(where: { $0.hasSuffix(".xcodeproj") }) {
			return (iosFlashscorePath as NSString).appendingPathComponent(project)
		}

		return nil
	}

	/// Checks if an Xcode project or workspace exists in the configured iOS subfolder
	/// - Parameters:
	///   - repositoryPath: The repository root path
	///   - iosSubfolderPath: The iOS subfolder path (e.g., "ios/FlashScore")
	/// - Returns: True if a project or workspace exists
	static func hasXcodeProject(in repositoryPath: String, iosSubfolderPath: String) -> Bool {
		findXcodeProject(in: repositoryPath, iosSubfolderPath: iosSubfolderPath) != nil
	}

	/// Returns the iOS subfolder path for a repository
	/// - Parameters:
	///   - repositoryPath: The repository root path
	///   - iosSubfolderPath: The iOS subfolder path (e.g., "ios/FlashScore")
	/// - Returns: Full path to iOS subfolder
	static func getIosFlashscorePath(in repositoryPath: String, iosSubfolderPath: String) -> String {
		(repositoryPath as NSString).appendingPathComponent(iosSubfolderPath)
	}
}
