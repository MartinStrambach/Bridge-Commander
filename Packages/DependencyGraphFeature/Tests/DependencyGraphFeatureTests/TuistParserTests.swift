import Testing

@testable import DependencyGraphFeature

@Suite("Tuist parser")
struct TuistParserTests {

	private let registry = """
	public extension FrameworkDependency where Self == Framework<AppKind> {
		static var AppCore: Self { Self("AppCore") }
		static var AppBase: Self { Self("AppBase") }
	}

	public extension FrameworkDependency where Self == Framework<CoreKind> {
		static var SharedDI: Self { Self("SharedDI", kmpName: "di") }
		static var AppMultiplatformCore: Self { Self("AppMultiplatformCore") }
	}

	public extension FrameworkDependency where Self == Framework<WidgetKind> {
		static var PlayerStatisticsCardWidget: Self { Self(
			"PlayerStatisticsCardWidget",
			kmpName: "player-stats-card"
		) }
	}

	public extension FrameworkDependency where Self == Framework<MainKind> {
		static var SharedTesting: Self { Self("SharedTesting", kmpName: "testing/core") }
	}
	"""

	@Test
	func registryMembersAndKinds() {
		#expect(TuistParser.frameworks(inRegistry: registry) == [
			.init(member: "AppCore", name: "AppCore", kind: "app", kmpName: nil),
			.init(member: "AppBase", name: "AppBase", kind: "app", kmpName: nil),
			.init(member: "SharedDI", name: "SharedDI", kind: "core", kmpName: "di"),
			.init(member: "AppMultiplatformCore", name: "AppMultiplatformCore", kind: "core", kmpName: nil),
			.init(
				member: "PlayerStatisticsCardWidget",
				name: "PlayerStatisticsCardWidget",
				kind: "widget",
				kmpName: "player-stats-card"
			),
			.init(member: "SharedTesting", name: "SharedTesting", kind: "main", kmpName: "testing/core"),
		])
	}

	@Test
	func targetsSplitRegularAndTestDependencies() {
		let targets = """
		Target.frameworkWithUnitTests(
			.AppCore,
			application: application,
			internalDependencies: [.SharedDI, .AppMultiplatformCore],
			externalDependencies: [.composableArchitecture, .swiftLog],
			testsResources: [
				"\\(K.frameworksRelativePath)/\\(Framework<AppKind>.AppCore.name)/Tests/sample.feed"
			],
			testsInternalDependencies: [
				.SharedTesting,
				.AppMultiplatformCore,
			],
		)
		Target.sharedFramework(
			.SharedDI,
			application: application
		)
		Target.appTarget(for: .MyApp)
		Target.appExtension(
			.notificationContent,
			internalDependencies: [.AppCore],
			externalDependencies: [.userNotificationsUI],
			application: application,
		)
		"""

		let known: Set = ["AppCore", "SharedDI", "AppMultiplatformCore", "SharedTesting"]
		#expect(TuistParser.targets(in: targets, known: known) == [
			.init(
				name: "AppCore",
				isExtension: false,
				dependencies: ["SharedDI", "AppMultiplatformCore"],
				testDependencies: ["SharedTesting", "AppMultiplatformCore"]
			),
			.init(name: "SharedDI", isExtension: false, dependencies: [], testDependencies: []),
			.init(name: "notificationContent", isExtension: true, dependencies: ["AppCore"], testDependencies: []),
		])
	}

	@Test
	func dependenciesListedByAFunction() {
		let list = """
		static func frameworkDependencies(for application: Application) -> [any FrameworkDependency] {
			let deps: [any FrameworkDependency] = [
				.AppCore,
				.SharedDI,
			]
			let extra: [any FrameworkDependency] = switch application {
			case .BrandB: [.SharedTesting]
			case .BrandA: [.unknown]
			}
			return deps + extra
		}
		"""
		let builder = """
		static func appBase(for application: Application) -> Self {
			let framework = Framework<AppKind>.AppBase
			let internalDependencies = frameworkDependencies(for: application)
			return .target(name: framework.name, dependencies: internalDependencies.map(\\.targetDependency))
		}
		static func unrelated() -> Self {
			let framework = Framework<AppKind>.AppCore
			return .target(name: framework.name)
		}
		"""

		let known: Set = ["AppBase", "AppCore", "SharedDI", "SharedTesting"]
		let listed = TuistParser.listedDependencies(in: [list, builder], known: known)
		#expect(listed.count == 1)
		#expect(listed.first?.target == "AppBase")
		#expect(listed.first?.dependencies == ["AppCore", "SharedDI", "SharedTesting"])
	}
}
