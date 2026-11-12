import Foundation

public enum XcodeFilePreference: String, Codable, Equatable, Sendable, CaseIterable {
	case auto
	case workspace
	case project

	public var displayName: String {
		switch self {
		case .auto: "Auto"
		case .workspace: "Workspace"
		case .project: "Project"
		}
	}
}

public nonisolated enum XcodeProjectDetector {

	/// Finds an Xcode workspace or project in the configured iOS subfolder
	/// - Parameters:
	///   - repositoryPath: The repository root path
	///   - iosSubfolderPath: The iOS subfolder path (e.g., "ios/MyApp")
	/// - Returns: Path to .xcworkspace or .xcodeproj, or nil if not found
	/// - Note: Prioritizes .xcworkspace over .xcodeproj
	public static func findXcodeProject(
		in repositoryPath: String,
		iosSubfolderPath: String,
		preference: XcodeFilePreference = .auto
	) -> String? {
		let fileManager = FileManager.default

		// Build path to iOS subfolder
		let iosFolderPath = Self.iosFolderPath(in: repositoryPath, iosSubfolderPath: iosSubfolderPath)

		// Check that the iOS subfolder exists
		var isDirectory: ObjCBool = false
		guard
			fileManager.fileExists(atPath: iosFolderPath, isDirectory: &isDirectory),
			isDirectory.boolValue
		else {
			return nil
		}

		// Get directory contents
		guard let contents = try? fileManager.contentsOfDirectory(atPath: iosFolderPath) else {
			return nil
		}

		switch preference {
		case .auto:
			if let workspace = contents.first(where: { $0.hasSuffix(".xcworkspace") }) {
				return (iosFolderPath as NSString).appendingPathComponent(workspace)
			}
			if let project = contents.first(where: { $0.hasSuffix(".xcodeproj") }) {
				return (iosFolderPath as NSString).appendingPathComponent(project)
			}
		case .workspace:
			if let workspace = contents.first(where: { $0.hasSuffix(".xcworkspace") }) {
				return (iosFolderPath as NSString).appendingPathComponent(workspace)
			}
		case .project:
			if let project = contents.first(where: { $0.hasSuffix(".xcodeproj") }) {
				return (iosFolderPath as NSString).appendingPathComponent(project)
			}
		}

		return nil
	}

	/// Checks if an Xcode project or workspace exists in the configured iOS subfolder
	/// - Parameters:
	///   - repositoryPath: The repository root path
	///   - iosSubfolderPath: The iOS subfolder path (e.g., "ios/MyApp")
	/// - Returns: True if a project or workspace exists
	public static func hasXcodeProject(in repositoryPath: String, iosSubfolderPath: String) -> Bool {
		findXcodeProject(in: repositoryPath, iosSubfolderPath: iosSubfolderPath) != nil
	}

	/// Returns the iOS subfolder path for a repository
	/// - Parameters:
	///   - repositoryPath: The repository root path
	///   - iosSubfolderPath: The iOS subfolder path (e.g., "ios/MyApp")
	/// - Returns: Full path to iOS subfolder
	public static func iosFolderPath(in repositoryPath: String, iosSubfolderPath: String) -> String {
		(repositoryPath as NSString).appendingPathComponent(iosSubfolderPath)
	}

	/// Checks whether the iOS subfolder contains Tuist manifest files
	/// - Parameters:
	///   - repositoryPath: The repository root path
	///   - iosSubfolderPath: The iOS subfolder path (e.g., "ios/MyApp")
	/// - Returns: True if Tuist manifests are detected
	public static func hasTuistManifest(in repositoryPath: String, iosSubfolderPath: String) -> Bool {
		let folderPath = iosFolderPath(in: repositoryPath, iosSubfolderPath: iosSubfolderPath)
		let fileManager = FileManager.default
		let tuistIndicators = ["Project.swift", "Workspace.swift", "Tuist"]
		return tuistIndicators.contains { indicator in
			fileManager.fileExists(atPath: (folderPath as NSString).appendingPathComponent(indicator))
		}
	}
}
