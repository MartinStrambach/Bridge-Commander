import Testing

@testable import DependencyGraphFeature

@Suite("Gradle parser")
struct GradleParserTests {

	// MARK: - Settings

	@Test
	func includesWithAndWithoutProjectDir() {
		let settings = """
		rootProject.name = "app"
		// include(":commented-out")
		include(":core")
		project(":core").projectDir = File(rootProject.projectDir, "android/core")
		include (":components")
		project(":components").projectDir = File(rootProject.projectDir, "android/components/")
		include(":platform:core:feature-flags:api")
		include(":a", ":b")
		project(":b").projectDir = file("./libs/b")
		/* include(":block-commented") */
		maven { url = uri("https://example.com/repo") }
		include(":core")
		"""

		#expect(GradleParser.includedProjects(inSettings: settings) == [
			.init(path: ":core", directory: "android/core"),
			.init(path: ":components", directory: "android/components"),
			.init(path: ":platform:core:feature-flags:api", directory: "platform/core/feature-flags/api"),
			.init(path: ":a", directory: "a"),
			.init(path: ":b", directory: "libs/b"),
		])
	}

	// MARK: - Accessors

	@Test
	func accessorCamelCasesEachSegment() {
		#expect(GradleParser.accessor(forProjectPath: ":platform:core:feature-flags:api") == "platform.core.featureFlags.api")
		#expect(GradleParser.accessor(forProjectPath: ":shared-libs-push:testing") == "sharedLibsPush.testing")
		#expect(GradleParser.accessor(forProjectPath: ":snake_case") == "snakeCase")
		#expect(GradleParser.accessor(forProjectPath: ":archTest") == "archTest")
	}

	@Test
	func resolveTriesShorterChains() {
		let map = ["core": ":core", "core.ui": ":core:ui"]
		#expect(GradleParser.resolve(accessor: "core.ui", in: map) == ":core:ui")
		#expect(GradleParser.resolve(accessor: "core.dependencyProject", in: map) == ":core")
		#expect(GradleParser.resolve(accessor: "unknown", in: map) == nil)
	}

	// MARK: - Build files

	@Test
	func androidModuleDependencies() {
		let build = """
		plugins {
		    alias(libs.plugins.android.library)
		}
		dependencies {
		    implementation(libs.android.appcompat)
		    implementation(projects.core)
		    api(projects.platform.widget.search)
		    StoreImplementation(projects.storeServices)
		    brandA_comImplementation(projects.sharedResourcesBrandA)
		    testImplementation(projects.coreTest)
		    implementation(project.dependencies.platform(libs.compose.bom))
		    AppProjects.projects.values.forEach { println(it) }
		    // implementation(projects.commentedOut)
		}
		"""

		let file = GradleParser.parseBuildFile(build)
		#expect(file.kind == .android)
		#expect(file.exportsIOSFramework == false)
		#expect(file.dependencies == [
			.init(target: .accessor("core"), configuration: "implementation", isTest: false),
			.init(target: .accessor("platform.widget.search"), configuration: "api", isTest: false),
			.init(target: .accessor("storeServices"), configuration: "StoreImplementation", isTest: false),
			.init(
				target: .accessor("sharedResourcesBrandA"),
				configuration: "brandA_comImplementation",
				isTest: false
			),
			.init(target: .accessor("coreTest"), configuration: "testImplementation", isTest: true),
		])
	}

	@Test
	func androidModuleDependingOnKMPModuleStaysAndroid() {
		let build = """
		plugins {
		    alias(libs.plugins.android.library)
		}
		dependencies {
		    implementation(projects.multiplatformSearch)
		    implementation(projects.multiplatform)
		}
		"""
		#expect(GradleParser.parseBuildFile(build).kind == .android)
	}

	@Test
	func kmpSourceSetsMarkTestDependencies() {
		let build = """
		plugins {
		    alias(libs.plugins.multiplatform.library)
		}
		kotlin {
		    sourceSets {
		        commonMain.dependencies {
		            implementation(projects.platform.components)
		            compileOnly(projects.platform.testing.annotations)
		        }
		        androidMain.dependencies { implementation(projects.platform.core.resources.api) }
		        commonTest.dependencies {
		            implementation(projects.platform.service.event.impl)
		        }
		        getByName("androidDeviceTest").dependencies {
		            implementation(projects.platform.testing.core)
		        }
		    }
		}
		"""

		let file = GradleParser.parseBuildFile(build)
		#expect(file.kind == .kmp)
		#expect(file.dependencies.map(\.isTest) == [false, false, false, true, true])
		#expect(file.dependencies.map(\.target) == [
			.accessor("platform.components"),
			.accessor("platform.testing.annotations"),
			.accessor("platform.core.resources.api"),
			.accessor("platform.service.event.impl"),
			.accessor("platform.testing.core"),
		])
	}

	@Test
	func braceOnItsOwnLineTakesThePreviousLineAsLabel() {
		let build = """
		kotlin {
		    sourceSets {
		        val commonTest by getting
		        {
		            dependencies {
		                implementation(projects.core)
		            }
		        }
		    }
		}
		"""
		#expect(GradleParser.parseBuildFile(build).dependencies.first?.isTest == true)
	}

	@Test
	func umbrellaExportsAndLiteralProjectPaths() {
		let build = """
		plugins {
		    alias(libs.plugins.multiplatform.ios.umbrella)
		}
		kotlin {
		    framework {
		        export(projects.multiplatform)
		    }
		}
		dependencies {
		    "detektPlugins"(project(":lint-rules"))
		    implementation(project(path = ":core", configuration = "default"))
		    create("release") { from(project(":android:baseline")) }
		}
		"""

		let file = GradleParser.parseBuildFile(build)
		#expect(file.kind == .kmp)
		#expect(file.exportsIOSFramework)
		#expect(file.dependencies.map(\.target) == [
			.accessor("multiplatform"),
			.path(":lint-rules"),
			.path(":core"),
		])
	}

	@Test
	func moduleKinds() {
		#expect(GradleParser.parseBuildFile("plugins { id(\"org.jetbrains.kotlin.jvm\") }").kind == .jvm)
		#expect(GradleParser.parseBuildFile("plugins { alias(libs.plugins.java.library) }").kind == .jvm)
		#expect(GradleParser.parseBuildFile("plugins { alias(libs.plugins.android.application) }").kind == .android)
		#expect(GradleParser.parseBuildFile("apply plugin: 'com.android.library'").kind == .android)
		#expect(GradleParser.parseBuildFile("plugins { kotlin(\"multiplatform\") }").kind == .kmp)
	}

	@Test
	func commentStrippingKeepsStringsAndLines() {
		let text = """
		val url = "https://example.com" // trailing
		/* block
		comment */ val x = 1
		"""
		#expect(GradleParser.strippingComments(text) == "val url = \"https://example.com\" \n\n val x = 1")
	}
}
