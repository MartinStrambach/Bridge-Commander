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

/// The tool that writes a repository's Xcode project from a manifest, when it has one.
public nonisolated enum ProjectGenerator: Equatable, Sendable {
	case tuist
	case xcodeGen

	public var displayName: String {
		switch self {
		case .tuist: "Tuist"
		case .xcodeGen: "XcodeGen"
		}
	}

	/// What the Xcode button's generate runs, for its labels.
	public var generateDescription: String {
		switch self {
		case .tuist: "tuist install & generate"
		case .xcodeGen: "xcodegen generate"
		}
	}
}

public nonisolated enum XcodeProjectDetector {
	/// The spec file names XcodeGen reads by default, in the order it looks for them.
	static let xcodeGenSpecNames = ["project.yml", "project.json"]


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

	/// The XcodeGen spec in the iOS subfolder (`project.yml`, else `project.json`), or nil
	/// - Parameters:
	///   - repositoryPath: The repository root path
	///   - iosSubfolderPath: The iOS subfolder path (e.g., "ios/MyApp")
	public static func xcodeGenSpecPath(in repositoryPath: String, iosSubfolderPath: String) -> String? {
		let folderPath = iosFolderPath(in: repositoryPath, iosSubfolderPath: iosSubfolderPath)
		return xcodeGenSpecNames
			.map { (folderPath as NSString).appendingPathComponent($0) }
			.first { FileManager.default.fileExists(atPath: $0) }
	}

	/// The generator whose manifest the iOS subfolder holds. Tuist wins when both are present:
	/// a Tuist project may keep an old XcodeGen spec around while migrating, never the reverse.
	public static func projectGenerator(in repositoryPath: String, iosSubfolderPath: String) -> ProjectGenerator? {
		if hasTuistManifest(in: repositoryPath, iosSubfolderPath: iosSubfolderPath) {
			return .tuist
		}
		if xcodeGenSpecPath(in: repositoryPath, iosSubfolderPath: iosSubfolderPath) != nil {
			return .xcodeGen
		}
		return nil
	}
}
