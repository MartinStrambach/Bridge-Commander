import Testing

@testable import DependencyGraphFeature

@Suite("Dependency graph loader")
struct DependencyGraphLoaderTests {

	/// A repository held in memory: file contents by relative path; folders are implied.
	private func fileSystem(_ files: [String: String]) -> DependencyGraphLoader.FileSystem {
		DependencyGraphLoader.FileSystem(
			read: { files[$0] },
			swiftFiles: { directory in
				files.keys.filter { $0.hasPrefix(directory + "/") && $0.hasSuffix(".swift") }.sorted()
			},
			directoryExists: { directory in
				files.keys.contains { $0.hasPrefix(directory + "/") }
			}
		)
	}

	private let repository: [String: String] = [
		"settings.gradle.kts": """
		include(":app")
		project(":app").projectDir = File(rootProject.projectDir, "android/app")
		include(":platform:widget:event-list")
		include(":umbrella")
		include(":platform")
		""",
		"android/app/build.gradle.kts": """
		plugins { alias(libs.plugins.android.application) }
		dependencies {
		    implementation(projects.platform.widget.eventList)
		    implementation(projects.platform)
		    testImplementation(projects.app)
		}
		""",
		"platform/widget/event-list/build.gradle.kts": """
		plugins { alias(libs.plugins.multiplatform.library) }
		""",
		"umbrella/build.gradle.kts": """
		plugins { alias(libs.plugins.multiplatform.ios.umbrella) }
		kotlin { framework { export(projects.platform.widget.eventList) } }
		""",
		"platform/widget/event-list/ios/Sources/View.swift": "",
		"ios/Frameworks/AppMultiplatformCore/Sources/File.swift": "",
		"ios/Frameworks/AppBase/Sources/File.swift": "",
		"ios/Tuist/ProjectDescriptionHelpers/Framework.swift": """
		public extension FrameworkDependency where Self == Framework<AppKind> {
			static var AppBase: Self { Self("AppBase") }
		}
		public extension FrameworkDependency where Self == Framework<CoreKind> {
			static var AppMultiplatformCore: Self { Self("AppMultiplatformCore") }
		}
		public extension FrameworkDependency where Self == Framework<WidgetKind> {
			static var EventListWidget: Self { Self("EventListWidget", kmpName: "event-list") }
		}
		""",
		"ios/Tuist/ProjectDescriptionHelpers/Targets/Frameworks.swift": """
		Target.sharedFramework(.EventListWidget, application: application, internalDependencies: [.AppMultiplatformCore])
		static func frameworkDependencies(for application: Application) -> [any FrameworkDependency] {
			[.EventListWidget]
		}
		""",
		"ios/Tuist/ProjectDescriptionHelpers/Targets/AppBase.swift": """
		static func appBase(for application: Application) -> Self {
			let framework = Framework<AppKind>.AppBase
			return .target(name: framework.name, dependencies: frameworkDependencies(for: application).map(\\.targetDependency))
		}
		""",
	]

	@Test
	func readsGradleAndTuistModulesAndLinksThem() {
		let graph = DependencyGraphLoader.load(iosSubfolderPath: "", fileSystem: fileSystem(repository))

		#expect(graph.modules.map(\.id) == [
			":app",
			":platform:widget:event-list",
			":umbrella",
			"ios:AppBase",
			"ios:AppMultiplatformCore",
			"ios:EventListWidget",
		])
		#expect(graph.modules.first { $0.id == "ios:EventListWidget" }?.directories == ["platform/widget/event-list/ios"])
		#expect(graph.modules.first { $0.id == ":app" }?.kind == .android)

		// `:platform` has no build file, so it is no module and the edge to it is dropped; the
		// self edge from a test configuration is dropped too.
		#expect(Set(graph.edges) == [
			DependencyEdge(from: ":app", to: ":platform:widget:event-list", isTest: false),
			DependencyEdge(from: ":umbrella", to: ":platform:widget:event-list", isTest: false),
			DependencyEdge(from: "ios:EventListWidget", to: "ios:AppMultiplatformCore", isTest: false),
			DependencyEdge(from: "ios:EventListWidget", to: ":platform:widget:event-list", isTest: false),
			DependencyEdge(from: "ios:AppMultiplatformCore", to: ":umbrella", isTest: false),
			DependencyEdge(from: "ios:AppBase", to: "ios:EventListWidget", isTest: false),
		])
	}

	@Test
	func anAmbiguousKMPNameLinksNothing() {
		var files = repository
		files["other/event-list/build.gradle.kts"] = "plugins { alias(libs.plugins.multiplatform.library) }"
		files["other/event-list/ios/Sources/Other.swift"] = ""
		files["settings.gradle.kts"]! += "\ninclude(\":other:event-list\")"

		let graph = DependencyGraphLoader.load(iosSubfolderPath: "", fileSystem: fileSystem(files))
		#expect(!graph.edges.contains { $0.from == "ios:EventListWidget" && !$0.to.hasPrefix("ios:") })
	}

	@Test
	func aKMPFolderThatOnlyHoldsModulesStillGivesTheFrameworkItsFolder() {
		var files = repository
		files["settings.gradle.kts"]! += "\ninclude(\":platform:core:resources:api\")"
		files["platform/core/resources/api/build.gradle.kts"] = "plugins { alias(libs.plugins.multiplatform.library) }"
		files["platform/core/resources/ios/Sources/Resources.swift"] = ""
		files["ios/Tuist/ProjectDescriptionHelpers/Resources.swift"] = """
		public extension FrameworkDependency where Self == Framework<CoreKind> {
			static var ResourcesCore: Self { Self("ResourcesCore", kmpName: "resources") }
		}
		"""

		let graph = DependencyGraphLoader.load(iosSubfolderPath: "", fileSystem: fileSystem(files))
		#expect(graph.modules.first { $0.id == "ios:ResourcesCore" }?.directories == ["platform/core/resources/ios"])
		// No module sits in `platform/core/resources` itself, so there is nothing to link.
		#expect(!graph.edges.contains { $0.from == "ios:ResourcesCore" })
	}

	@Test
	func repositoryWithoutBuildFilesHasNoModules() {
		let graph = DependencyGraphLoader.load(iosSubfolderPath: "", fileSystem: fileSystem(["README.md": ""]))
		#expect(graph.modules.isEmpty)
		#expect(graph.platforms.isEmpty)
	}

	@Test
	func regularDeclarationWinsOverTestOne() {
		let graph = DependencyGraph(modules: [], edges: [
			DependencyEdge(from: "a", to: "b", isTest: true),
			DependencyEdge(from: "a", to: "b", isTest: false),
			DependencyEdge(from: "a", to: "c", isTest: true),
		])
		#expect(graph.edges == [
			DependencyEdge(from: "a", to: "b", isTest: false),
			DependencyEdge(from: "a", to: "c", isTest: true),
		])
	}

	@Test
	func titlesAndSubtitles() {
		let api = DependencyModule(id: ":platform:news:api", kind: .kmp, directories: ["platform/news/api"])
		#expect(api.title == "news:api")
		#expect(api.subtitle == ":platform")

		let topLevel = DependencyModule(id: ":core-ui", kind: .android, directories: ["android/core-ui"])
		#expect(topLevel.title == "core-ui")
		#expect(topLevel.subtitle == "android/core-ui")

		let framework = DependencyModule(id: "ios:AppCore", kind: .iosFramework, directories: [])
		#expect(framework.name == "AppCore")
		#expect(framework.title == "AppCore")
		#expect(framework.subtitle == "iOS framework")
	}
}
