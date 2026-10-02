import ComposableArchitecture
import Foundation
import GitCore
import Testing
import ToolsIntegration
@testable import RepositoryFeature

// The terminal toolbar's Xcode button is the opened row's own store. It used to be a copy held in
// `TerminalLayoutReducer.State`, and hiding the panel nils that state — `ifLet` then cancelled the
// generate effect, SIGTERMing tuist with no error shown, and the row never learned it had run.
@Suite("Terminal toolbar Xcode button shares the row's state")
@MainActor
struct TerminalSharedXcodeButtonTests {
	@Test("a generate keeps running and lands on the row after the terminal is hidden")
	func generateSurvivesHidingTerminal() async {
		let (gate, release) = AsyncStream.makeStream(of: Void.self)
		let opened = LockIsolated<[String]>([])
		let store = await makeStoreShowingAlpha {
			$0[XcodeClient.self].generateProject = { _, _, _, _, _, onStateChange in
				await onStateChange(.runningTi)
				// Held here until the terminal has been hidden.
				for await _ in gate { break }
				await onStateChange(.runningTg)
				return "/repos/alpha/App.xcworkspace"
			}
			$0[XcodeClient.self].openProject = { path in
				opened.withValue { $0.append(path) }
			}
		}

		await store.send(xcodeAction(.openProject))
		await store.send(xcodeAction(.alert(.presented(.confirmGenerate))))
		await store.receive(\.repositoryGroups[id: "/repos/alpha"].header.xcodeButton.projectGenerationProgress)
		#expect(alphaXcodeButton(in: store)?.projectState == .runningTi)

		await store.send(.terminalLayout(.hideTerminalMode))
		#expect(store.state.terminalLayout == nil)
		// Still in progress on the row, which is what the list shows once the terminal is gone.
		#expect(alphaXcodeButton(in: store)?.projectState == .runningTi)

		release.yield()
		await store.receive(\.repositoryGroups[id: "/repos/alpha"].header.xcodeButton.projectGenerationProgress)
		#expect(alphaXcodeButton(in: store)?.projectState == .runningTg)
		await store.receive(\.repositoryGroups[id: "/repos/alpha"].header.xcodeButton.didGenerateProject)
		await store.receive(\.repositoryGroups[id: "/repos/alpha"].header.xcodeButton.didOpenProject)

		#expect(alphaXcodeButton(in: store)?.projectPath == "/repos/alpha/App.xcworkspace")
		#expect(alphaXcodeButton(in: store)?.projectState == .idle)
		#expect(opened.value == ["/repos/alpha/App.xcworkspace"])
	}

	@Test("the terminal toolbar keeps no Xcode button state of its own")
	func terminalLayoutHoldsNoXcodeCopy() async throws {
		// Opening a repository in the terminal re-syncs the toolbar's copied buttons. The Xcode
		// button must not be among them, or progress shown in one view would not show in the other.
		let store = await makeStoreShowingAlpha { _ in }
		let layout = try #require(store.state.terminalLayout)

		let labels = Mirror(reflecting: layout).children.compactMap(\.label)
		#expect(!labels.contains { $0.localizedCaseInsensitiveContains("xcode") })
		#expect(!labels.contains { $0.localizedCaseInsensitiveContains("tuist") })
	}

	// MARK: - Helpers

	private func xcodeAction(_ action: XcodeProjectButtonReducer.Action) -> RepositoryListReducer.Action {
		.repositoryGroups(.element(id: "/repos/alpha", action: .header(.xcodeButton(action))))
	}

	private func alphaXcodeButton(
		in store: TestStoreOf<RepositoryListReducer>
	) -> XcodeProjectButtonReducer.State? {
		store.state.repositoryGroups[id: "/repos/alpha"]?.header.xcodeButton
	}

	/// One scanned repository, opened in the terminal panel.
	private func makeStoreShowingAlpha(
		_ dependencies: @escaping (inout DependencyValues) -> Void
	) async -> TestStoreOf<RepositoryListReducer> {
		var initialState = RepositoryListReducer.State()
		initialState.terminalLayout = TerminalLayoutReducer.State()
		let store = TestStore(initialState: initialState) {
			RepositoryListReducer()
		} withDependencies: {
			$0.continuousClock = ImmediateClock()
			$0[GitClient.self].getCurrentBranch = { _ in
				GitPorcelainStatus(parsing: "", didSucceed: false)
			}
			$0[GitClient.self].getOriginRemote = { _ in nil }
			$0[XcodeClient.self].findXcodeProject = { _, _, _ in nil }
			$0[LastOpenedDirectoryClient.self].load = { nil }
			dependencies(&$0)
		}
		store.exhaustivity = .off
		await store.send(.didScanGroup(rootPath: "/repos/alpha", rows: [
			ScannedRepository(
				path: "/repos/alpha",
				name: "alpha",
				directory: "/repos/alpha",
				isWorktree: false,
				branchName: "master"
			),
		]))
		await store.send(.terminalLayout(.selectRepo(repositoryPath: "/repos/alpha")))
		return store
	}
}
