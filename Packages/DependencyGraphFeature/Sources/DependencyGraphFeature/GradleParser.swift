import Foundation

/// Reads Gradle's module structure from `settings.gradle(.kts)` and the modules' build files as
/// text: nothing is evaluated, so only the declarations written out literally are seen (see the
/// package README for the forms understood).
enum GradleParser {

	// MARK: - Settings

	struct IncludedProject: Equatable {
		/// ":a:b"
		let path: String
		/// Relative to the settings file's folder, without a trailing slash.
		let directory: String
	}

	/// The `include(...)`d projects, each in the folder a `project(":x").projectDir = …` line
	/// moves it to, else in Gradle's default (the path with ":" turned into "/"). Order follows
	/// the first include.
	static func includedProjects(inSettings text: String) -> [IncludedProject] {
		let source = strippingComments(text)

		var paths: [String] = []
		var seen: Set<String> = []
		for match in source.matches(of: includeCall) {
			for quoted in String(match.output.1).matches(of: quotedString) {
				let path = normalizedProjectPath(String(quoted.output.1))
				if !path.isEmpty, seen.insert(path).inserted {
					paths.append(path)
				}
			}
		}

		var remapped: [String: String] = [:]
		for match in source.matches(of: projectDirAssignment) {
			remapped[normalizedProjectPath(String(match.output.1))] = normalizedDirectory(String(match.output.2))
		}

		return paths.map { path in
			IncludedProject(
				path: path,
				directory: remapped[path] ?? path.split(separator: ":").joined(separator: "/")
			)
		}
	}

	// MARK: - Build file

	struct BuildFile: Equatable {
		var kind: ModuleKind
		var dependencies: [Dependency]
		/// Declares `export(...)`: the module bundles others into the framework iOS links.
		var exportsIOSFramework: Bool
	}

	struct Dependency: Equatable {
		enum Target: Equatable {
			/// What follows `projects.`, e.g. "platform.core.featureFlags.api".
			case accessor(String)
			/// A literal path, e.g. ":core".
			case path(String)
		}

		let target: Target
		let configuration: String
		let isTest: Bool
	}

	static func parseBuildFile(_ text: String) -> BuildFile {
		let source = strippingComments(text)
		var dependencies: [Dependency] = []

		// Each `{` is labelled with the code before it on its line ("commonTest.dependencies",
		// "getByName(\"androidDeviceTest\")"), or the previous line's when it stands alone, so a
		// dependency knows which source set it is declared in.
		var labels: [String] = []
		var previousLine = ""
		for line in source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
			var events: [(offset: Int, event: LineEvent)] = []
			var segmentStart = line.startIndex
			for index in line.indices where line[index] == "{" || line[index] == "}" {
				let offset = line.distance(from: line.startIndex, to: index)
				if line[index] == "{" {
					var label = line[segmentStart ..< index].trimmingCharacters(in: .whitespaces)
					if label.isEmpty {
						label = previousLine
					}
					events.append((offset, .open(label)))
				}
				else {
					events.append((offset, .close))
				}
				segmentStart = line.index(after: index)
			}
			for match in line.matches(of: dependencyCall) {
				let configuration = match.output.1
				let offset = line.distance(from: line.startIndex, to: configuration.startIndex)
				guard isDependencyConfiguration(String(configuration)) else {
					continue
				}

				let target: Dependency.Target = if let accessor = match.output.2 {
					.accessor(String(accessor))
				}
				else {
					.path(normalizedProjectPath(String(match.output.3 ?? "")))
				}
				events.append((offset, .dependency(target, String(configuration))))
			}

			for (_, event) in events.sorted(by: { $0.offset < $1.offset }) {
				switch event {
				case let .open(label):
					labels.append(label)
				case .close:
					_ = labels.popLast()
				case let .dependency(target, configuration):
					let isTest = configuration.localizedCaseInsensitiveContains("test")
						|| labels.contains { $0.localizedCaseInsensitiveContains("test") }
					dependencies.append(Dependency(target: target, configuration: configuration, isTest: isTest))
				}
			}

			let trimmed = line.trimmingCharacters(in: .whitespaces)
			if !trimmed.isEmpty {
				previousLine = trimmed
			}
		}

		return BuildFile(
			kind: moduleKind(of: source),
			dependencies: dependencies,
			exportsIOSFramework: dependencies.contains { $0.configuration == "export" }
		)
	}

	private enum LineEvent {
		case open(String)
		case close
		case dependency(Dependency.Target, String)
	}

	/// KMP if a multiplatform plugin is applied, Android if an Android plugin is, JVM otherwise.
	/// Checked in that order: a KMP module applies Android's KMP library plugin too. Only the
	/// `plugins { }` block is read when there is one, so a dependency named
	/// `projects.multiplatformSearch` does not make an Android module KMP.
	static func moduleKind(of fullSource: String) -> ModuleKind {
		let source = pluginsBlock(in: fullSource) ?? fullSource
		let kmpMarkers = [
			"plugins.multiplatform", "kotlin(\"multiplatform\")", "kotlin.multiplatform", "multiplatform.library",
		]
		if kmpMarkers.contains(where: source.contains) {
			return .kmp
		}
		let androidMarkers = [
			"com.android.", "plugins.android.library", "plugins.android.application", "plugins.android.test",
			"android.library", "android.application",
		]
		if androidMarkers.contains(where: source.contains) {
			return .android
		}
		return .jvm
	}

	/// The contents of the top-level `plugins { … }` block.
	static func pluginsBlock(in source: String) -> String? {
		guard let match = source.firstMatch(of: /(?m)^\s*plugins\s*\{/) else {
			return nil
		}

		var depth = 0
		var index = source.index(before: match.range.upperBound)
		let start = match.range.upperBound
		while index < source.endIndex {
			switch source[index] {
			case "{":
				depth += 1
			case "}":
				depth -= 1
				if depth == 0 {
					return String(source[start ..< index])
				}
			default:
				break
			}
			index = source.index(after: index)
		}
		return String(source[start...])
	}

	// MARK: - Accessors

	/// Gradle's type-safe accessor for a project path: each segment camel-cased at "-" and "_",
	/// joined with "." (":shared-libs-push:testing" → "sharedLibsPush.testing").
	static func accessor(forProjectPath path: String) -> String {
		path.split(separator: ":").map { segment in
			let words = segment.split(whereSeparator: { $0 == "-" || $0 == "_" })
			guard let first = words.first else {
				return String(segment)
			}
			return String(first) + words.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
		}
		.joined(separator: ".")
	}

	/// The project an accessor chain names, trying shorter chains when it is followed by
	/// something else (`projects.core.dependencyProject`).
	static func resolve(accessor: String, in accessorToPath: [String: String]) -> String? {
		var segments = accessor.split(separator: ".")
		while !segments.isEmpty {
			if let path = accessorToPath[segments.joined(separator: ".")] {
				return path
			}
			segments.removeLast()
		}
		return nil
	}

	// MARK: - Helpers

	/// Configurations that put a project on a classpath (any variant or flavour prefix:
	/// `testImplementation`, `GooglePlayImplementation`) or bundle it (`export`, `lintChecks`,
	/// `detektPlugins`). Excludes calls like `from(project(...))`.
	private static func isDependencyConfiguration(_ name: String) -> Bool {
		let lowercased = name.lowercased()
		return dependencyConfigurationSuffixes.contains(where: lowercased.hasSuffix)
	}

	private static let dependencyConfigurationSuffixes = [
		"implementation", "api", "compileonly", "runtimeonly", "export", "lintchecks", "detektplugins", "ksp", "kapt",
	]

	static func normalizedProjectPath(_ path: String) -> String {
		let trimmed = path.trimmingCharacters(in: .whitespaces)
		guard !trimmed.isEmpty else {
			return ""
		}
		return trimmed.hasPrefix(":") ? trimmed : ":" + trimmed
	}

	static func normalizedDirectory(_ directory: String) -> String {
		var result = directory
		while result.hasPrefix("./") {
			result.removeFirst(2)
		}
		while result.hasSuffix("/") {
			result.removeLast()
		}
		return result
	}

	/// Removes `//` and `/* */` comments outside string literals, keeping line breaks so line
	/// structure survives.
	static func strippingComments(_ text: String) -> String {
		var result = ""
		result.reserveCapacity(text.utf8.count)
		var characters = text.makeIterator()
		var pending: Character? = nil
		var inString = false
		var inLineComment = false
		var inBlockComment = false

		func next() -> Character? {
			if let character = pending {
				pending = nil
				return character
			}
			return characters.next()
		}

		while let character = next() {
			if inLineComment {
				if character == "\n" {
					inLineComment = false
					result.append(character)
				}
				continue
			}
			if inBlockComment {
				if character == "*" {
					let following = next()
					if following == "/" {
						inBlockComment = false
					}
					else {
						pending = following
					}
				}
				else if character == "\n" {
					result.append(character)
				}
				continue
			}
			if inString {
				result.append(character)
				if character == "\\" {
					if let escaped = next() {
						result.append(escaped)
					}
				}
				else if character == "\"" || character == "\n" {
					inString = false
				}
				continue
			}

			switch character {
			case "\"":
				inString = true
				result.append(character)
			case "/":
				let following = next()
				if following == "/" {
					inLineComment = true
				}
				else if following == "*" {
					inBlockComment = true
				}
				else {
					result.append(character)
					pending = following
				}
			default:
				result.append(character)
			}
		}
		return result
	}

	// MARK: - Patterns

	/// `include(":a", ":b")`, also with a space before the parenthesis.
	nonisolated(unsafe) private static let includeCall = /\binclude\s*\(([^)]*)\)/

	nonisolated(unsafe) private static let quotedString = /"([^"]*)"/

	/// `project(":x").projectDir = File(rootProject.projectDir, "dir")` or `= file("dir")`.
	nonisolated(unsafe) private static let projectDirAssignment =
		/project\(\s*"([^"]+)"\s*\)\.projectDir\s*=\s*(?:File\(\s*[A-Za-z.]+\s*,\s*|file\(\s*)"([^"]+)"\s*\)/

	/// `configuration(projects.a.b)` or `configuration(project(":a"))`; the configuration may be
	/// quoted (`"detektPlugins"(project(":rules"))`).
	nonisolated(unsafe) private static let dependencyCall =
		/(?:^|[^\w."])"?([A-Za-z_][A-Za-z0-9_]*)"?\s*\(\s*(?:projects\.([A-Za-z0-9_.]+)|project\(\s*(?:path\s*=\s*)?"([^"]*)"[^)]*\))/
}
