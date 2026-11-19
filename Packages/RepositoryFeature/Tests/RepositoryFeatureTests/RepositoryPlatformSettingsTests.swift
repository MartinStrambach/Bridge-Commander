import ActionButtons
import ComposableArchitecture
import Foundation
import GitCore
import Settings
import Testing
import ToolsIntegration
@testable import RepositoryFeature

// The iOS and macOS group toggles share the Xcode button, Tuist and the Xcode project path;
// only iOS brings the simulator and counts towards the mobile subfolder.
@Suite("Repository platform settings")
@MainActor
struct RepositoryPlatformSettingsTests {
	@Test("a row uses Xcode for iOS, macOS or both")
	func rowUsesXcode() {
		#expect(!row().usesXcode)
		#expect(row(supportsIOS: true).usesXcode)
		#expect(row(supportsMacOS: true).usesXcode)
		#expect(row(supportsIOS: true, supportsMacOS: true).usesXcode)
	}

	@Test("a macOS group's rows get the Xcode project path but stay non-iOS")
	func macOSGroupRows() async {
		@Shared(.groupSettings) var groupSettings: [String: RepoGroupSettings] = [:]
		$groupSettings.withLock {
			$0 = ["/repos/mac": RepoGroupSettings(supportsMacOS: true, iosSubfolderPath: "App", supportsTuist: true)]
		}
		let store = makeStore()
		store.exhaustivity = .off

		await store.send(.didScanGroup(rootPath: "/repos/mac", rows: [mainRepo("/repos/mac")]))

		let header = store.state.repositoryGroups[id: "/repos/mac"]?.header
		#expect(header?.supportsMacOS == true)
		#expect(header?.supportsIOS == false)
		#expect(header?.usesXcode == true)
		#expect(header?.supportsTuist == true)
		#expect(header?.xcodeButton.iosSubfolderPath == "App")
		#expect(header?.tuistButton.iosSubfolderPath == "App")
	}

	@Test("switching a group from iOS to macOS updates its existing rows")
	func groupSettingsChangeAppliesMacOS() async {
		@Shared(.groupSettings) var groupSettings: [String: RepoGroupSettings] = [:]
		$groupSettings.withLock { $0 = ["/repos/app": RepoGroupSettings(supportsIOS: true)] }
		let store = makeStore()
		store.exhaustivity = .off

		await store.send(.didScanGroup(rootPath: "/repos/app", rows: [mainRepo("/repos/app")]))
		#expect(store.state.repositoryGroups[id: "/repos/app"]?.header.supportsIOS == true)

		$groupSettings.withLock { $0 = ["/repos/app": RepoGroupSettings(supportsMacOS: true, iosSubfolderPath: "mac")] }
		await store.send(.view(.groupSettingsChanged))

		let header = store.state.repositoryGroups[id: "/repos/app"]?.header
		#expect(header?.supportsIOS == false)
		#expect(header?.supportsMacOS == true)
		#expect(header?.usesXcode == true)
		#expect(header?.xcodeButton.iosSubfolderPath == "mac")
	}

	@Test("macOS with Android does not move tools into the mobile subfolder")
	func macOSIsNotMobile() async {
		@Shared(.groupSettings) var groupSettings: [String: RepoGroupSettings] = [:]
		$groupSettings.withLock {
			$0 = ["/repos/mac": RepoGroupSettings(supportsMacOS: true, supportsAndroid: true, mobileSubfolderPath: "mobile")]
		}
		let store = makeStore()
		store.exhaustivity = .off

		await store.send(.didScanGroup(rootPath: "/repos/mac", rows: [mainRepo("/repos/mac")]))

		let header = store.state.repositoryGroups[id: "/repos/mac"]?.header
		#expect(header?.mobileSubfolderPath == "")
		#expect(header?.androidStudioButton.mobileSubfolderPath == "")
	}

	// MARK: - Helpers

	private func row(supportsIOS: Bool = false, supportsMacOS: Bool = false) -> RepositoryRowReducer.State {
		RepositoryRowReducer.State(
			path: "/repos/app",
			name: "app",
			branchName: "main",
			supportsIOS: supportsIOS,
			supportsMacOS: supportsMacOS
		)
	}

	private func makeStore() -> TestStoreOf<RepositoryListReducer> {
		TestStore(initialState: RepositoryListReducer.State()) {
			RepositoryListReducer()
		} withDependencies: {
			$0.continuousClock = ImmediateClock()
			$0[GitClient.self].getCurrentBranch = { _ in
				GitPorcelainStatus(parsing: "", didSucceed: false)
			}
			$0[XcodeClient.self].findXcodeProject = { _, _, _ in nil }
			$0[LastOpenedDirectoryClient.self].load = { nil }
		}
	}

	private func mainRepo(_ path: String) -> ScannedRepository {
		ScannedRepository(
			path: path,
			name: URL(fileURLWithPath: path).lastPathComponent,
			directory: path,
			isWorktree: false,
			branchName: "master"
		)
	}
}
