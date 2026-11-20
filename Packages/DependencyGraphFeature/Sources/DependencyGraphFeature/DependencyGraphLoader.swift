import Foundation

/// Builds a repository's `DependencyGraph` from its Gradle settings and build files and its Tuist
/// helpers. Reads files synchronously; the client runs it on its own queue.
enum DependencyGraphLoader {

	/// Reads a file relative to the repository root; nil when it does not exist.
	typealias FileReader = (_ relativePath: String) -> String?
	/// Lists the `.swift` files under a folder relative to the root, as relative paths.
	typealias SwiftFileLister = (_ relativeDirectory: String) -> [String]
	typealias DirectoryExists = (_ relativePath: String) -> Bool

	struct FileSystem {
		var read: FileReader
		var swiftFiles: SwiftFileLister
		var directoryExists: DirectoryExists
	}

	static func load(iosSubfolderPath: String, fileSystem: FileSystem) -> DependencyGraph {
		let gradle = gradleModules(fileSystem: fileSystem)
		let ios = iosModules(iosSubfolderPath: iosSubfolderPath, gradleModules: gradle, fileSystem: fileSystem)
		return DependencyGraph(modules: gradle.modules + ios.modules, edges: gradle.edges + ios.edges)
	}

	// MARK: - Gradle

	struct GradleModules {
		var modules: [DependencyModule] = []
		var edges: [DependencyEdge] = []
		/// Modules that bundle others into the framework iOS links (`export(...)`).
		var iosUmbrellas: [String] = []
	}

	static func gradleModules(fileSystem: FileSystem) -> GradleModules {
		guard let settings = fileSystem.read("settings.gradle.kts") ?? fileSystem.read("settings.gradle") else {
			return GradleModules()
		}

		let projects = GradleParser.includedProjects(inSettings: settings)
		let accessorToPath = Dictionary(
			projects.map { (GradleParser.accessor(forProjectPath: $0.path), $0.path) },
			uniquingKeysWith: { first, _ in first }
		)

		var result = GradleModules()
		// A path Gradle includes only as a parent (":platform") has no build file and is no
		// module.
		var buildFiles: [(project: GradleParser.IncludedProject, file: GradleParser.BuildFile)] = []
		for project in projects {
			let prefix = project.directory.isEmpty ? "" : project.directory + "/"
			guard let text = fileSystem.read(prefix + "build.gradle.kts") ?? fileSystem.read(prefix + "build.gradle") else {
				continue
			}
			buildFiles.append((project, GradleParser.parseBuildFile(text)))
		}

		let modulePaths = Set(buildFiles.map(\.project.path))
		for (project, file) in buildFiles {
			result.modules.append(DependencyModule(id: project.path, kind: file.kind, directories: [project.directory]))
			if file.exportsIOSFramework {
				result.iosUmbrellas.append(project.path)
			}
			for dependency in file.dependencies {
				let target: String? = switch dependency.target {
				case let .accessor(accessor): GradleParser.resolve(accessor: accessor, in: accessorToPath)
				case let .path(path): path
				}
				if let target, modulePaths.contains(target) {
					result.edges.append(DependencyEdge(from: project.path, to: target, isTest: dependency.isTest))
				}
			}
		}
		return result
	}

	// MARK: - iOS

	static func iosModules(
		iosSubfolderPath: String,
		gradleModules: GradleModules,
		fileSystem: FileSystem
	) -> (modules: [DependencyModule], edges: [DependencyEdge]) {
		let candidates = [iosSubfolderPath, "ios", ""]
			.map(GradleParser.normalizedDirectory)
		guard let iosRoot = candidates.first(where: { fileSystem.directoryExists(helpersDirectory(in: $0)) }) else {
			return ([], [])
		}

		let files = fileSystem.swiftFiles(helpersDirectory(in: iosRoot)).compactMap(fileSystem.read)
		let frameworks = files.flatMap(TuistParser.frameworks(inRegistry:))
		guard !frameworks.isEmpty else {
			return ([], [])
		}

		let byMember = Dictionary(frameworks.map { ($0.member, $0) }, uniquingKeysWith: { first, _ in first })
		let known = Set(byMember.keys)
		func id(ofMember member: String) -> String? {
			byMember[member].map { DependencyModule.iosPrefix + $0.name }
		}

		let kmpFolders = kmpFolders(of: frameworks, gradleModules: gradleModules, fileSystem: fileSystem)
		var modules: [DependencyModule] = frameworks.map { framework in
			let local = iosRoot.isEmpty ? "Frameworks/\(framework.name)" : "\(iosRoot)/Frameworks/\(framework.name)"
			let candidates = [kmpFolders[framework.name].map { $0.folder + "/ios" }, local].compactMap(\.self)
			return DependencyModule(
				id: DependencyModule.iosPrefix + framework.name,
				kind: .iosFramework,
				directories: candidates.filter(fileSystem.directoryExists)
			)
		}
		var edges: [DependencyEdge] = []

		for text in files {
			for target in TuistParser.targets(in: text, known: known) {
				let from: String
				if target.isExtension {
					from = DependencyModule.iosPrefix + extensionName(target.name)
					if !modules.contains(where: { $0.id == from }) {
						modules.append(DependencyModule(id: from, kind: .iosExtension, directories: []))
					}
				}
				else if let frameworkID = id(ofMember: target.name) {
					from = frameworkID
				}
				else {
					continue
				}

				edges += target.dependencies.compactMap(id(ofMember:)).map {
					DependencyEdge(from: from, to: $0, isTest: false)
				}
				edges += target.testDependencies.compactMap(id(ofMember:)).map {
					DependencyEdge(from: from, to: $0, isTest: true)
				}
			}
		}

		for (target, dependencies) in TuistParser.listedDependencies(in: files, known: known) {
			guard let from = id(ofMember: target) else {
				continue
			}
			edges += dependencies.compactMap(id(ofMember:)).map { DependencyEdge(from: from, to: $0, isTest: false) }
		}

		// iOS frameworks linking Kotlin: one with a `kmpName` links the KMP module it wraps, and
		// one with "Multiplatform" in its name embeds the framework the umbrella modules export.
		for framework in frameworks {
			let from = DependencyModule.iosPrefix + framework.name
			if let kmpFolder = kmpFolders[framework.name] {
				if let moduleID = kmpFolder.moduleID {
					edges.append(DependencyEdge(from: from, to: moduleID, isTest: false))
				}
			}
			else if framework.name.contains("Multiplatform") {
				edges += gradleModules.iosUmbrellas.map { DependencyEdge(from: from, to: $0, isTest: false) }
			}
		}
		return (modules, edges)
	}

	/// Where each framework with a `kmpName` keeps its sources, and the Gradle module there:
	/// the one folder among the Gradle modules' folders and their parents that ends in that name
	/// and holds an `ios/` folder (the module may be a child, like `resources/api`). Matching on
	/// the folder's tail keeps the repository's folder layout out of the code; an ambiguous name
	/// matches nothing.
	static func kmpFolders(
		of frameworks: [TuistParser.Framework],
		gradleModules: GradleModules,
		fileSystem: FileSystem
	) -> [String: (folder: String, moduleID: String?)] {
		var moduleByDirectory: [String: String] = [:]
		var folders: Set<String> = []
		for module in gradleModules.modules {
			for directory in module.directories where !directory.isEmpty {
				moduleByDirectory[directory] = module.id
				var components = directory.split(separator: "/")
				while !components.isEmpty {
					folders.insert(components.joined(separator: "/"))
					components.removeLast()
				}
			}
		}

		var result: [String: (folder: String, moduleID: String?)] = [:]
		for framework in frameworks {
			guard let kmpName = framework.kmpName.map(GradleParser.normalizedDirectory), !kmpName.isEmpty else {
				continue
			}

			let matches = folders.filter { folder in
				(folder == kmpName || folder.hasSuffix("/" + kmpName)) && fileSystem.directoryExists(folder + "/ios")
			}
			if matches.count == 1, let folder = matches.first {
				result[framework.name] = (folder, moduleByDirectory[folder])
			}
		}
		return result
	}

	private static func helpersDirectory(in iosRoot: String) -> String {
		iosRoot.isEmpty ? "Tuist/ProjectDescriptionHelpers" : iosRoot + "/Tuist/ProjectDescriptionHelpers"
	}

	/// `.notificationContent` → "NotificationContent".
	private static func extensionName(_ member: String) -> String {
		member.prefix(1).uppercased() + member.dropFirst()
	}
}

// MARK: - Live file system

extension DependencyGraphLoader.FileSystem {
	static func live(repositoryPath: String) -> Self {
		let root = URL(filePath: repositoryPath, directoryHint: .isDirectory)
		return Self(
			read: { relativePath in
				try? String(contentsOf: root.appending(path: relativePath), encoding: .utf8)
			},
			swiftFiles: { relativeDirectory in
				let directory = root.appending(path: relativeDirectory, directoryHint: .isDirectory)
				guard let enumerator = FileManager.default.enumerator(
					at: directory,
					includingPropertiesForKeys: nil,
					options: [.skipsHiddenFiles]
				) else {
					return []
				}

				let prefix = relativeDirectory.isEmpty ? "" : relativeDirectory + "/"
				return enumerator.compactMap { $0 as? URL }
					.filter { $0.pathExtension == "swift" }
					.map { url in
						let components = url.standardizedFileURL.pathComponents
						let base = directory.standardizedFileURL.pathComponents
						return prefix + components.dropFirst(base.count).joined(separator: "/")
					}
					.sorted()
			},
			directoryExists: { relativePath in
				var isDirectory: ObjCBool = false
				return FileManager.default.fileExists(atPath: root.appending(path: relativePath).path, isDirectory: &isDirectory)
					&& isDirectory.boolValue
			}
		)
	}
}
