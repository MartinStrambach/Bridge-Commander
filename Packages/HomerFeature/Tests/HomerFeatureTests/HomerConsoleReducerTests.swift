import ComposableArchitecture
import DependenciesTestSupport
import Foundation
@testable import HomerFeature
import Testing

/// `.dependencies` gives every test fresh dependencies, and with them its own app storage: the
/// instance list is `@Shared`, and tests running in parallel would otherwise see each other's.
@MainActor
@Suite("Homer console instances", .dependencies)
struct HomerConsoleReducerTests {
	private static let first = "https://homer.example.com"
	private static let second = "http://localhost:8080"
	private let admin = HomerUser(username: "admin", role: "admin")
	private let question = HomerQuestion(
		id: "q-1",
		processId: 7,
		agentName: "factory",
		text: "Ship it?",
		options: ["Yes", "No"],
		createdAt: 1_700_000_000
	)

	/// Build the state before handing it to `TestStore`, never inline: its `initialState` is an
	/// autoclosure evaluated inside the store's own dependencies, so the `@Shared` values written
	/// here would land in a different app storage than the one the store's expectations read.
	private func signedInState(selected: String) -> HomerConsoleReducer.State {
		var state = HomerConsoleReducer.State()
		state.$instanceURLs.withLock { $0 = [Self.first, Self.second] }
		state.$selectedInstanceID.withLock { $0 = selected }
		state.hasStarted = true
		for baseURL in [Self.first, Self.second] {
			var instance = HomerInstanceReducer.State(baseURL: baseURL)
			instance.session = .signedIn(admin)
			state.instances.append(instance)
		}
		return state
	}

	@Test("with no instance yet, the add form opens and cannot be cancelled")
	func startWithoutInstances() async {
		let store = TestStore(initialState: HomerConsoleReducer.State()) {
			HomerConsoleReducer()
		}

		await store.send(.start) {
			$0.hasStarted = true
			$0.addInstance = HomerSignInReducer.State(addingInstanceCanCancel: false)
		}
	}

	@Test("every remembered instance checks its own session at launch")
	func startChecksEveryInstance() async {
		let checked = LockIsolated<[String]>([])
		let initialState = HomerConsoleReducer.State()
		initialState.$instanceURLs.withLock { $0 = [Self.first, Self.second] }
		let store = TestStore(initialState: initialState) {
			HomerConsoleReducer()
		} withDependencies: {
			$0[HomerClient.self].me = { baseURL in
				checked.withValue { $0.append(baseURL) }
				throw HomerAPIError.unauthorized
			}
		}

		await store.send(.start) {
			$0.hasStarted = true
			$0.instances = [
				HomerInstanceReducer.State(baseURL: Self.first),
				HomerInstanceReducer.State(baseURL: Self.second),
			]
			// None remembered yet: the first is shown.
			$0.$selectedInstanceID.withLock { $0 = Self.first }
		}
		store.exhaustivity = .off(showSkippedAssertions: false)
		await store.receive(\.instances[id: Self.first].sessionChecked)
		await store.receive(\.instances[id: Self.second].sessionChecked)

		#expect(Set(checked.value) == [Self.first, Self.second])
		#expect(store.state.instances.allSatisfy { $0.session == .signedOut })
	}

	@Test("only the instance on screen lists its processes; switching hands the polling over")
	func switchingMovesProcessPolling() async {
		let listed = LockIsolated<[String]>([])
		let store = TestStore(initialState: signedInState(selected: Self.first)) {
			HomerConsoleReducer()
		} withDependencies: {
			$0.continuousClock = TestClock()
			$0[HomerClient.self].processes = { baseURL, _ in
				listed.withValue { $0.append(baseURL) }
				return HomerProcessPage(processes: [], total: 0)
			}
			$0[HomerClient.self].agentNames = { _ in [] }
			$0[HomerClient.self].openQuestions = { _ in [] }
			$0[HomerContinuationsClient.self].pendingCount = { _ in 0 }
		}
		store.exhaustivity = .off(showSkippedAssertions: false)

		await store.send(.appeared)
		await store.receive(\.instances[id: Self.first].processesLoaded)
		#expect(listed.value == [Self.first])

		await store.send(.instanceSelected(Self.second))
		await store.receive(\.instances[id: Self.second].processesLoaded)

		#expect(listed.value == [Self.first, Self.second])
		#expect(store.state.selectedInstanceID == Self.second)
		#expect(store.state.instances[id: Self.first]?.isActive == false)
		#expect(store.state.instances[id: Self.second]?.isActive == true)
		await store.skipInFlightEffects()
	}

	@Test("the badge counts every instance's open questions")
	func questionCountsAcrossInstances() {
		var state = signedInState(selected: Self.first)
		state.instances[id: Self.second]?.questions = [question]

		#expect(state.openQuestionCount == 1)
		#expect(state.otherInstancesOpenQuestionCount == 1)

		// A signed-out instance's last questions are not waiting on anyone.
		state.instances[id: Self.second]?.session = .signedOut
		#expect(state.openQuestionCount == 0)
	}

	@Test("an added instance is signed in, remembered and shown")
	func addInstance() async {
		let clock = TestClock()
		var initialState = HomerConsoleReducer.State()
		initialState.$instanceURLs.withLock { $0 = [Self.first] }
		initialState.$selectedInstanceID.withLock { $0 = Self.first }
		initialState.hasStarted = true
		var existing = HomerInstanceReducer.State(baseURL: Self.first)
		existing.session = .signedIn(admin)
		initialState.instances = [existing]
		let store = TestStore(initialState: initialState) {
			HomerConsoleReducer()
		} withDependencies: {
			$0.continuousClock = clock
			$0[HomerClient.self].login = { _, _, _ in admin }
			$0[HomerClient.self].openQuestions = { _ in [] }
		}

		await store.send(.addInstanceTapped) {
			$0.addInstance = HomerSignInReducer.State(addingInstanceCanCancel: true)
		}
		await store.send(.addInstance(.binding(.set(\.endpoint, "http://localhost:8080/processes")))) {
			$0.addInstance?.endpoint = "http://localhost:8080/processes"
		}
		await store.send(.addInstance(.binding(.set(\.username, "admin")))) {
			$0.addInstance?.username = "admin"
		}
		await store.send(.addInstance(.binding(.set(\.password, "secret")))) {
			$0.addInstance?.password = "secret"
		}
		await store.send(.addInstance(.signInTapped)) {
			$0.addInstance?.endpoint = Self.second
			$0.addInstance?.isSigningIn = true
		}
		await store.receive(\.addInstance.signInFinished) {
			$0.addInstance?.isSigningIn = false
			$0.addInstance?.password = ""
			// Written by the delegate action below, which runs within the same effect: a
			// `@Shared` value is already the new one when this step is compared.
			$0.$instanceURLs.withLock { $0 = [Self.first, Self.second] }
			$0.$selectedInstanceID.withLock { $0 = Self.second }
		}
		await store.receive(\.addInstance.delegate.signedIn) {
			$0.addInstance = nil
			$0.instances.append(HomerInstanceReducer.State(baseURL: Self.second))
			// The expectation's state reads the username the step below already remembered;
			// the instance itself was made before it.
			$0.instances[id: Self.second]?.signIn.username = ""
		}
		await store.receive(\.instances[id: Self.second].signedIn) {
			$0.instances[id: Self.second]?.session = .signedIn(admin)
			$0.instances[id: Self.second]?.signIn.username = "admin"
		}
		await store.receive(\.instances[id: Self.second].questionsLoaded) {
			$0.instances[id: Self.second]?.hasLoadedQuestions = true
		}
		await store.skipInFlightEffects()
	}

	@Test("removing the instance on screen signs it out and shows the next")
	func removeSelectedInstance() async {
		let signedOut = LockIsolated<[String]>([])
		@Shared(.homerUsernames) var usernames
		$usernames.withLock { $0 = [Self.first: "admin", Self.second: "admin"] }
		let store = TestStore(initialState: signedInState(selected: Self.first)) {
			HomerConsoleReducer()
		} withDependencies: {
			$0[HomerClient.self].logout = { baseURL in signedOut.withValue { $0.append(baseURL) } }
		}

		await store.send(.removeInstanceTapped(Self.first)) {
			$0.instances.remove(id: Self.first)
			$0.$instanceURLs.withLock { $0 = [Self.second] }
			$0.$selectedInstanceID.withLock { $0 = Self.second }
		}
		await store.finish()

		#expect(signedOut.value == [Self.first])
		#expect(usernames == [Self.second: "admin"])
	}

	@Test("removing the last instance brings back the first-run form")
	func removeLastInstance() async {
		var initialState = signedInState(selected: Self.first)
		initialState.instances.remove(id: Self.second)
		initialState.$instanceURLs.withLock { $0 = [Self.first] }
		let store = TestStore(initialState: initialState) {
			HomerConsoleReducer()
		} withDependencies: {
			$0[HomerClient.self].logout = { _ in }
		}

		await store.send(.removeInstanceTapped(Self.first)) {
			$0.instances = []
			$0.$instanceURLs.withLock { $0 = [] }
			$0.$selectedInstanceID.withLock { $0 = "" }
			$0.addInstance = HomerSignInReducer.State(addingInstanceCanCancel: false)
		}
		await store.finish()
	}

	@Test("picking an instance from the menu leaves the add form")
	func selectingLeavesAddForm() async {
		var initialState = signedInState(selected: Self.first)
		initialState.addInstance = HomerSignInReducer.State(addingInstanceCanCancel: true)
		let store = TestStore(initialState: initialState) {
			HomerConsoleReducer()
		}

		await store.send(.instanceSelected(Self.second)) {
			$0.addInstance = nil
			$0.$selectedInstanceID.withLock { $0 = Self.second }
		}
	}
}
