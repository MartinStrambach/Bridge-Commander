import Foundation
import ProcessExecution

/// A scheme whose Run action launches an app — what the pane's Run button can build and start.
public struct XcodeScheme: Equatable, Identifiable, Sendable {
	public var name: String
	/// The app the Run action launches, as it is named in the build products ("FlashScore.app");
	/// `nil` for a scheme Xcode makes up, which has no file to read it from — the run script then
	/// takes the first app among the targets the scheme builds.
	public var productName: String?

	public var id: String { name }

	public init(name: String, productName: String?) {
		self.name = name
		self.productName = productName
	}
}

/// Finds the runnable schemes of a workspace or project by reading their `.xcscheme` files rather
/// than asking `xcodebuild -list`, which lists every framework and test scheme with no way to tell
/// which of them launch an app: a Tuist workspace has around a hundred schemes, of which a handful
/// run something.
///
/// A project with no scheme files at all (XcodeGen without `schemes:`, a project whose schemes
/// Xcode makes up per target) has its schemes listed by `xcodebuild -list` instead, unfiltered.
public nonisolated enum XcodeSchemeScanner {
	/// The runnable schemes of the `.xcworkspace` or `.xcodeproj` at `containerPath`, sorted by
	/// name — or, when it has no scheme files, every scheme `xcodebuild -list` names.
	public static func schemes(in containerPath: String, userName: String = NSUserName()) async -> [XcodeScheme] {
		let scan = scanSchemeFiles(in: containerPath, userName: userName)
		guard !scan.foundSchemeFiles else {
			return scan.schemes
		}

		let flag = containerPath.hasSuffix(".xcworkspace") ? "-workspace" : "-project"
		let result = await ProcessRunner.run(
			executableURL: URL(fileURLWithPath: "/usr/bin/xcrun"),
			arguments: ["xcodebuild", "-list", "-json", flag, containerPath]
		)
		guard result.success else {
			return []
		}
		return schemeNames(inListJSON: result.output)
			.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
			.map { XcodeScheme(name: $0, productName: nil) }
	}

	/// The schemes `xcodebuild -list -json` printed, for a workspace or a project.
	static func schemeNames(inListJSON data: Data) -> [String] {
		struct Listing: Decodable {
			struct Container: Decodable {
				var schemes: [String]?
			}

			var workspace: Container?
			var project: Container?
		}

		guard let listing = try? JSONDecoder().decode(Listing.self, from: data) else {
			return []
		}
		return listing.workspace?.schemes ?? listing.project?.schemes ?? []
	}

	/// The runnable schemes among the container's scheme files, sorted by name: shared ones and
	/// `userName`'s own, from the container and, for a workspace, from every project it
	/// references. A name found twice keeps the first. `foundSchemeFiles` tells a container whose
	/// schemes all launch nothing from one that has no scheme files.
	static func scanSchemeFiles(in containerPath: String, userName: String) -> (schemes: [XcodeScheme], foundSchemeFiles: Bool) {
		let fileManager = FileManager.default
		var containers = [containerPath]
		if containerPath.hasSuffix(".xcworkspace") {
			let contentsPath = (containerPath as NSString).appendingPathComponent("contents.xcworkspacedata")
			if let data = fileManager.contents(atPath: contentsPath) {
				let workspaceDirectory = (containerPath as NSString).deletingLastPathComponent
				containers += projectPaths(inWorkspaceContents: data, workspaceDirectory: workspaceDirectory)
			}
		}

		var schemes: [XcodeScheme] = []
		var seen: Set<String> = []
		var foundSchemeFiles = false
		for container in containers {
			let folders = [
				"xcshareddata/xcschemes",
				"xcuserdata/\(userName).xcuserdatad/xcschemes",
			].map { (container as NSString).appendingPathComponent($0) }

			for folder in folders {
				let files = (try? fileManager.contentsOfDirectory(atPath: folder)) ?? []
				for file in files.sorted() where file.hasSuffix(".xcscheme") {
					foundSchemeFiles = true
					let name = (file as NSString).deletingPathExtension
					guard
						!seen.contains(name),
						let data = fileManager.contents(atPath: (folder as NSString).appendingPathComponent(file)),
						let product = runnableProductName(inScheme: data)
					else {
						continue
					}
					seen.insert(name)
					schemes.append(XcodeScheme(name: name, productName: product))
				}
			}
		}
		let sorted = schemes.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
		return (sorted, foundSchemeFiles)
	}

	/// The `.app` a scheme's Run action launches (its `LaunchAction`'s `BuildableProductRunnable`),
	/// or `nil` when it launches nothing or something else — a test bundle, a command-line tool.
	static func runnableProductName(inScheme data: Data) -> String? {
		let delegate = SchemeParserDelegate()
		let parser = XMLParser(data: data)
		parser.delegate = delegate
		parser.parse()
		guard let name = delegate.productName, name.hasSuffix(".app") else {
			return nil
		}
		return name
	}

	/// The `.xcodeproj`s a workspace's `contents.xcworkspacedata` references, as absolute paths.
	/// A location is relative to the enclosing group (`group:`), to the workspace's folder
	/// (`container:`), or absolute (`absolute:`); groups nest.
	static func projectPaths(inWorkspaceContents data: Data, workspaceDirectory: String) -> [String] {
		let delegate = WorkspaceParserDelegate(workspaceDirectory: workspaceDirectory)
		let parser = XMLParser(data: data)
		parser.delegate = delegate
		parser.parse()
		return delegate.projectPaths
	}
}

private nonisolated final class SchemeParserDelegate: NSObject, XMLParserDelegate {
	private var isInLaunchAction = false
	private var isInRunnable = false
	private(set) var productName: String?

	func parser(
		_ parser: XMLParser,
		didStartElement elementName: String,
		namespaceURI: String?,
		qualifiedName: String?,
		attributes: [String: String] = [:]
	) {
		switch elementName {
		case "LaunchAction":
			isInLaunchAction = true
		case "BuildableProductRunnable" where isInLaunchAction:
			isInRunnable = true
		case "BuildableReference" where isInRunnable && productName == nil:
			productName = attributes["BuildableName"]
		default:
			break
		}
	}

	func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
		switch elementName {
		case "LaunchAction":
			isInLaunchAction = false
		case "BuildableProductRunnable":
			isInRunnable = false
		default:
			break
		}
	}
}

private nonisolated final class WorkspaceParserDelegate: NSObject, XMLParserDelegate {
	private let workspaceDirectory: String
	/// The folder each open `Group` stands for, innermost last.
	private var groupFolders: [String]
	private(set) var projectPaths: [String] = []

	init(workspaceDirectory: String) {
		self.workspaceDirectory = workspaceDirectory
		self.groupFolders = [workspaceDirectory]
	}

	private func resolve(_ location: String?) -> String? {
		guard let location, let colon = location.firstIndex(of: ":") else {
			return nil
		}
		let kind = location[..<colon]
		let path = String(location[location.index(after: colon)...])
		switch kind {
		case "group":
			return ((groupFolders.last ?? workspaceDirectory) as NSString).appendingPathComponent(path)
		case "container":
			return (workspaceDirectory as NSString).appendingPathComponent(path)
		case "absolute":
			return path
		default:
			return nil
		}
	}

	func parser(
		_ parser: XMLParser,
		didStartElement elementName: String,
		namespaceURI: String?,
		qualifiedName: String?,
		attributes: [String: String] = [:]
	) {
		switch elementName {
		case "Group":
			// A group with no location of its own is only a folder in the navigator.
			groupFolders.append(resolve(attributes["location"]) ?? groupFolders.last ?? workspaceDirectory)
		case "FileRef":
			if let path = resolve(attributes["location"]), path.hasSuffix(".xcodeproj") {
				projectPaths.append((path as NSString).standardizingPath)
			}
		default:
			break
		}
	}

	func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
		if elementName == "Group", groupFolders.count > 1 {
			groupFolders.removeLast()
		}
	}
}
