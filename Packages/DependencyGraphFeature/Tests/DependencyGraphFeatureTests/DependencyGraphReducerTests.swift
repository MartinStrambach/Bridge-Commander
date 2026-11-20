import ComposableArchitecture
import Foundation
import Testing

@testable import DependencyGraphFeature

@Suite("Dependency graph reducer")
@MainActor
struct DependencyGraphReducerTests {

	private let graph = DependencyGraph(
		modules: [
			DependencyModule(id: ":app", kind: .android, directories: ["android/app"]),
			DependencyModule(id: ":shared", kind: .kmp, directories: ["shared"]),
		],
		edges: [DependencyEdge(from: ":app", to: ":shared", isTest: false)]
	)

	private let changes = ModuleChanges(
		baseRef: "origin/master",
		mergeBase: "abc",
		newModules: [":shared"],
		changedModules: [],
		changedFileCounts: [":shared": 2]
	)

	private func store(highlightsChanges: Bool = true) -> TestStoreOf<DependencyGraphReducer> {
		let state = DependencyGraphReducer.State(
			repositoryPath: "/tmp/repo",
			repositoryName: "repo",
			iosSubfolderPath: "",
			configuredDefaultBranch: "develop"
		)
		state.$platform.withLock { $0 = .kmp }
		state.$highlightsChanges.withLock { $0 = highlightsChanges }
		state.$showsOtherPlatforms.withLock { $0 = true }
		state.$includesTestDependencies.withLock { $0 = false }

		let store = TestStore(initialState: state) {
			DependencyGraphReducer()
		} withDependencies: { [graph, changes] in
			$0[DependencyGraphClient.self].loadGraph = { _, _ in graph }
			$0[DependencyGraphClient.self].loadChanges = { _, defaultBranch, _ in
				#expect(defaultBranch == "develop")
				return changes
			}
		}
		store.exhaustivity = .off
		return store
	}

	@Test
	func loadsTheGraphThenTheBranchChanges() async {
		let store = store()

		await store.send(.task) {
			$0.isLoading = true
		}
		await store.receive(\.graphLoaded) {
			$0.isLoading = false
			$0.graph = graph
			$0.isLoadingChanges = true
		}
		#expect(store.state.platformGraph.modules.map(\.id) == [":shared"])
		await store.receive(\.changesLoaded) {
			$0.isLoadingChanges = false
			$0.changes = changes
		}
		#expect(store.state.visibleChanges == changes)
	}

	@Test
	func changesAreLoadedOnlyOnceHighlightingIsOn() async {
		let store = store(highlightsChanges: false)

		await store.send(.task)
		await store.receive(\.graphLoaded)
		#expect(store.state.changes == nil)
		#expect(store.state.isLoadingChanges == false)

		await store.send(.highlightsChangesToggled(true)) {
			$0.isLoadingChanges = true
		}
		await store.receive(\.changesLoaded) {
			$0.changes = changes
		}
	}

	@Test
	func switchingPlatformRebuildsAndDropsASelectionItNoLongerHolds() async {
		let store = store()
		await store.send(.task)
		await store.receive(\.graphLoaded)
		await store.receive(\.changesLoaded)

		await store.send(.moduleSelected(":shared")) {
			$0.selectedModuleID = ":shared"
		}
		let revision = store.state.layoutRevision

		await store.send(.showsOtherPlatformsToggled(false))
		await store.send(.platformSelected(.android)) {
			$0.selectedModuleID = nil
		}
		#expect(store.state.platformGraph.modules.map(\.id) == [":app"])
		#expect(store.state.layoutRevision == revision + 2)

		await store.send(.showsOtherPlatformsToggled(true))
		#expect(store.state.platformGraph.modules.map(\.id) == [":app", ":shared"])
		#expect(store.state.platformGraph.boundaryModuleIDs == [":shared"])
	}

	@Test
	func aMissingPlatformFallsBackToOneTheRepositoryHas() async {
		let store = store()
		await store.send(.platformSelected(.ios))
		await store.send(.task)
		await store.receive(\.graphLoaded)
		#expect(store.state.effectivePlatform == .kmp)
	}

	@Test
	func failingChangesShowTheErrorAndKeepTheGraph() async {
		let store = store()
		store.dependencies[DependencyGraphClient.self].loadChanges = { _, _, _ in
			throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "No common ancestor"])
		}

		await store.send(.task)
		await store.receive(\.graphLoaded)
		await store.receive(\.changesLoaded) {
			$0.isLoadingChanges = false
			$0.changesError = "No common ancestor"
		}
		#expect(store.state.graph == graph)
	}
}
