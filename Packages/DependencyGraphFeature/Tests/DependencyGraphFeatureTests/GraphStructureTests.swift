import CoreGraphics
import Testing

@testable import DependencyGraphFeature

@Suite("Change classification, platform graphs and layout")
struct GraphStructureTests {

	// MARK: - Change classification

	@Test
	func filesBelongToTheDeepestModuleFolder() {
		let modules = [
			DependencyModule(id: ":widget", kind: .kmp, directories: ["platform/widget"]),
			DependencyModule(id: "ios:WidgetUI", kind: .iosFramework, directories: ["platform/widget/ios"]),
			DependencyModule(id: ":user", kind: .kmp, directories: ["shared/user"]),
			DependencyModule(id: ":user:testing", kind: .kmp, directories: ["shared/user/testing"]),
			DependencyModule(id: ":untouched", kind: .kmp, directories: ["shared/untouched"]),
		]

		let result = ModuleChangeClassifier.classify(
			changedPaths: [
				"platform/widget/src/Widget.kt",
				"platform/widget/ios/Sources/Widget.swift",
				"platform/widget/ios/Sources/Other.swift",
				"shared/user/testing/src/Fake.kt",
				"README.md",
				"shared/untouchedness/file.kt",
			],
			modules: modules,
			existingDirectoriesAtBase: ["platform/widget", "platform/widget/ios", "shared/user", "shared/untouched"]
		)

		#expect(result.counts == [":widget": 1, "ios:WidgetUI": 2, ":user:testing": 1])
		#expect(result.new == [":user:testing"])
		#expect(result.changed == [":widget", "ios:WidgetUI"])
	}

	@Test
	func moduleWithSomeFolderAtBaseIsChangedNotNew() {
		let modules = [
			DependencyModule(id: "ios:Components", kind: .iosFramework, directories: ["platform/components/ios", "ios/Frameworks/Components"]),
		]
		let result = ModuleChangeClassifier.classify(
			changedPaths: ["ios/Frameworks/Components/File.swift"],
			modules: modules,
			existingDirectoriesAtBase: ["platform/components/ios"]
		)
		#expect(result.new.isEmpty)
		#expect(result.changed == ["ios:Components"])
	}

	// MARK: - Platform graph

	private let graph = DependencyGraph(
		modules: [
			DependencyModule(id: ":app", kind: .android, directories: []),
			DependencyModule(id: ":core", kind: .android, directories: []),
			DependencyModule(id: ":shared", kind: .kmp, directories: []),
			DependencyModule(id: ":shared:fake", kind: .kmp, directories: []),
			DependencyModule(id: ":javalib", kind: .jvm, directories: []),
		],
		edges: [
			DependencyEdge(from: ":app", to: ":core", isTest: false),
			DependencyEdge(from: ":app", to: ":shared", isTest: false),
			DependencyEdge(from: ":core", to: ":javalib", isTest: false),
			DependencyEdge(from: ":core", to: ":shared:fake", isTest: true),
			DependencyEdge(from: ":shared:fake", to: ":shared", isTest: false),
		]
	)

	@Test
	func otherPlatformsBecomeBoundaryNodes() {
		let android = PlatformGraph.make(from: graph, platform: .android, includesOtherPlatforms: true, includesTestDependencies: false)
		#expect(android.modules.map(\.id) == [":app", ":core", ":javalib", ":shared"])
		#expect(android.boundaryModuleIDs == [":shared"])
		// A boundary node's own dependencies are not followed.
		#expect(android.dependencies[":shared"] == nil)
		#expect(android.edges.count == 3)

		let withTests = PlatformGraph.make(from: graph, platform: .android, includesOtherPlatforms: true, includesTestDependencies: true)
		#expect(withTests.boundaryModuleIDs == [":shared", ":shared:fake"])

		let alone = PlatformGraph.make(from: graph, platform: .android, includesOtherPlatforms: false, includesTestDependencies: true)
		#expect(alone.modules.map(\.id) == [":app", ":core", ":javalib"])
		#expect(alone.boundaryModuleIDs.isEmpty)
	}

	@Test
	func transitiveClosures() {
		let kmpAndAndroid = DependencyGraph(modules: graph.modules.map {
			DependencyModule(id: $0.id, kind: .android, directories: [])
		}, edges: graph.edges)
		let all = PlatformGraph.make(from: kmpAndAndroid, platform: .android, includesOtherPlatforms: false, includesTestDependencies: true)

		#expect(all.transitiveDependencies(of: ":app") == [":core", ":shared", ":javalib", ":shared:fake"])
		#expect(all.transitiveDependents(of: ":shared") == [":app", ":shared:fake", ":core"])
		#expect(all.transitiveDependencies(of: ":javalib").isEmpty)
	}

	// MARK: - Layout

	@Test
	func dependentsSitAboveTheirDependenciesWithoutOverlap() {
		let ids = ["app", "feature-a", "feature-b", "core", "util"]
		let dependencies = [
			"app": ["feature-a", "feature-b", "core"],
			"feature-a": ["core"],
			"feature-b": ["core", "util"],
			"core": ["util"],
		]
		let layout = LayeredGraphLayout.layout(
			ids: ids,
			widths: Dictionary(uniqueKeysWithValues: ids.map { ($0, 150) }),
			dependencies: dependencies
		)

		#expect(layout.frames.count == ids.count)
		for (from, targets) in dependencies {
			for target in targets {
				#expect(layout.frames[from]!.maxY < layout.frames[target]!.minY, "\(from) should be above \(target)")
			}
		}
		let frames = Array(layout.frames.values)
		for (index, frame) in frames.enumerated() {
			for other in frames[(index + 1)...] {
				#expect(!frame.intersects(other))
			}
			#expect(CGRect(origin: .zero, size: layout.size).contains(frame))
		}
	}

	@Test
	func longestPathLayers() {
		let layers = LayeredGraphLayout.layers(
			ids: ["a", "b", "c", "d"],
			dependencies: ["a": ["b", "d"], "b": ["c"], "c": [], "d": []]
		)
		#expect(layers == ["a": 2, "b": 1, "c": 0, "d": 0])
	}

	@Test
	func cyclesDoNotHangOrCrash() {
		let ids = ["a", "b", "c"]
		let layout = LayeredGraphLayout.layout(
			ids: ids,
			widths: [:],
			dependencies: ["a": ["b"], "b": ["c"], "c": ["a"]]
		)
		#expect(layout.frames.count == 3)
	}

	@Test
	func wideLayersWrapIntoRows() {
		let ids = (0 ..< 60).map { "leaf\($0)" }
		let layout = LayeredGraphLayout.layout(
			ids: ids,
			widths: Dictionary(uniqueKeysWithValues: ids.map { ($0, 200) }),
			dependencies: [:]
		)
		let rows = Set(layout.frames.values.map(\.minY))
		#expect(rows.count > 1)
		#expect(layout.size.width < 60 * 200)
	}
}
