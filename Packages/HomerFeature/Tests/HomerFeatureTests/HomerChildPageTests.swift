import ComposableArchitecture
import DependenciesTestSupport
import Foundation
@testable import HomerFeature
import Testing

@MainActor
@Suite("Homer instance pages", .dependencies)
struct HomerChildPageTests {
	private static let baseURL = "https://homer.example.com"

	private func activeState(user: HomerUser) -> HomerInstanceReducer.State {
		var state = HomerInstanceReducer.State(baseURL: Self.baseURL)
		state.session = .signedIn(user)
		state.isActive = true
		return state
	}

	@Test("a page reducer is told when it comes on screen and when it leaves")
	func shownAndHidden() async {
		let initialState = activeState(user: HomerUser(username: "admin", role: "admin"))
		let store = TestStore(initialState: initialState) {
			HomerInstanceReducer()
		}

		await store.send(.pageChanged(.continuations)) {
			$0.page = .continuations
			$0.shownChildPage = .continuations
		}
		await store.receive(\.continuations.shown)

		// Agents and Schedules are one reducer: moving between them changes nothing.
		await store.send(.pageChanged(.agents)) {
			$0.page = .agents
			$0.shownChildPage = .agents
		}
		await store.receive(\.continuations.hidden)
		await store.receive(\.agents.shown)
		await store.send(.pageChanged(.schedules)) {
			$0.page = .schedules
		}

		await store.send(.deactivated) {
			$0.isActive = false
			$0.shownChildPage = nil
		}
		await store.receive(\.agents.hidden)
	}

	@Test("an admin-only page stays hidden for anyone else")
	func adminOnly() async {
		let initialState = activeState(user: HomerUser(username: "dev"))
		let store = TestStore(initialState: initialState) {
			HomerInstanceReducer()
		}

		await store.send(.pageChanged(.costs)) {
			$0.page = .costs
		}
	}

	@Test("a page's 401 signs the instance out, and its poll stops")
	func pageUnauthorized() async {
		var initialState = activeState(user: HomerUser(username: "admin", role: "admin"))
		initialState.page = .costs
		initialState.shownChildPage = .costs
		let store = TestStore(initialState: initialState) {
			HomerInstanceReducer()
		}

		await store.send(.costs(.delegate(.unauthorized))) {
			$0.session = .signedOut
			$0.signIn.sessionExpired = true
			$0.shownChildPage = nil
		}
		await store.receive(\.costs.hidden)
	}

	@Test("a page opens the web console in the instance's sheet")
	func pageOpensWebConsole() async {
		let initialState = activeState(user: HomerUser(username: "admin", role: "admin"))
		let store = TestStore(initialState: initialState) {
			HomerInstanceReducer()
		} withDependencies: {
			$0[HomerClient.self].sessionCookies = { _ in [] }
		}

		await store.send(.agents(.delegate(.openWebConsole(path: "agents/factory", title: "factory"))))
		await store.receive(\.openWebConsoleTapped) {
			$0.webPage = HomerWebPage(
				url: URL(string: "https://homer.example.com/agents/factory")!,
				title: "factory",
				cookies: [],
				dataStoreID: HomerEndpoint.webDataStoreID(baseURL: Self.baseURL)
			)
		}
	}
}
