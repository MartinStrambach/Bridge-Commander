import ComposableArchitecture
import DependenciesTestSupport
import Foundation
@testable import HomerFeature
import Testing

/// `.dependencies` gives every test fresh dependencies, and with them its own app storage: the
/// instance URL is `@Shared`, and tests running in parallel would otherwise see each other's.
@MainActor
@Suite("Homer console", .dependencies)
struct HomerConsoleReducerTests {
	private static let baseURL = "https://homer.example.com"
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
	/// autoclosure evaluated inside the store's own dependencies, so the `@Shared` URL written
	/// here would land in a different app storage than the one the store's expectations read.
	private func signedOutState(baseURL: String = Self.baseURL) -> HomerConsoleReducer.State {
		var state = HomerConsoleReducer.State()
		state.$baseURL.withLock { $0 = baseURL }
		state.session = .signedOut
		state.endpoint = baseURL
		return state
	}

	private func signedInState() -> HomerConsoleReducer.State {
		var state = signedOutState()
		state.session = .signedIn(admin)
		return state
	}

	@Test("with no instance yet, the sign-in form opens on the endpoint field")
	func startWithoutInstance() async {
		let store = TestStore(initialState: HomerConsoleReducer.State()) {
			HomerConsoleReducer()
		}

		await store.send(.start) {
			$0.session = .signedOut
			$0.isEditingEndpoint = true
		}
	}

	@Test("a stored session that is still valid signs straight in and starts polling questions")
	func startWithLiveSession() async {
		let clock = TestClock()
		let initialState = HomerConsoleReducer.State()
		initialState.$baseURL.withLock { $0 = Self.baseURL }
		let store = TestStore(initialState: initialState) {
			HomerConsoleReducer()
		} withDependencies: {
			$0.continuousClock = clock
			$0[HomerClient.self].me = { _ in admin }
			$0[HomerClient.self].openQuestions = { _ in [question] }
		}

		await store.send(.start) {
			$0.endpoint = Self.baseURL
		}
		await store.receive(\.sessionChecked) {
			$0.session = .signedIn(admin)
		}
		await store.receive(\.questionsLoaded) {
			$0.questions = [question]
			$0.hasLoadedQuestions = true
		}
		await store.skipInFlightEffects()
	}

	@Test("an expired cookie at launch shows the form without an error")
	func startWithExpiredCookie() async {
		let initialState = HomerConsoleReducer.State()
		initialState.$baseURL.withLock { $0 = Self.baseURL }
		let store = TestStore(initialState: initialState) {
			HomerConsoleReducer()
		} withDependencies: {
			$0[HomerClient.self].me = { _ in throw HomerAPIError.unauthorized }
		}

		await store.send(.start) {
			$0.endpoint = Self.baseURL
		}
		await store.receive(\.sessionChecked) {
			$0.session = .signedOut
		}
	}

	@Test("a pasted page URL signs in to its instance and is remembered")
	func signInStoresNormalizedInstance() async {
		let clock = TestClock()
		let loginArguments = LockIsolated<[String]>([])
		let initialState = signedOutState(baseURL: "")
		let store = TestStore(initialState: initialState) {
			HomerConsoleReducer()
		} withDependencies: {
			$0.continuousClock = clock
			$0[HomerClient.self].login = { baseURL, username, password in
				loginArguments.setValue([baseURL, username, password])
				return admin
			}
			$0[HomerClient.self].openQuestions = { _ in [] }
		}

		await store.send(.binding(.set(\.endpoint, "https://homer.example.com/processes"))) {
			$0.endpoint = "https://homer.example.com/processes"
		}
		await store.send(.binding(.set(\.username, " admin "))) {
			$0.username = " admin "
		}
		await store.send(.binding(.set(\.password, "secret"))) {
			$0.password = "secret"
		}
		await store.send(.signInTapped) {
			$0.endpoint = Self.baseURL
			$0.isSigningIn = true
		}
		await store.receive(\.signInFinished) {
			$0.$baseURL.withLock { $0 = Self.baseURL }
			$0.isSigningIn = false
			$0.password = ""
			$0.session = .signedIn(admin)
		}
		await store.receive(\.questionsLoaded) {
			$0.hasLoadedQuestions = true
		}

		#expect(loginArguments.value == [Self.baseURL, "admin", "secret"])
		await store.skipInFlightEffects()
	}

	@Test("a wrong password says so and keeps the form")
	func invalidCredentials() async {
		var initialState = signedOutState()
		initialState.username = "admin"
		initialState.password = "nope"
		let store = TestStore(initialState: initialState) {
			HomerConsoleReducer()
		} withDependencies: {
			$0[HomerClient.self].login = { _, _, _ in throw HomerAPIError.unauthorized }
		}

		await store.send(.signInTapped) {
			$0.isSigningIn = true
		}
		await store.receive(\.signInFinished) {
			$0.isSigningIn = false
			$0.loginError = "Invalid credentials. Please try again."
		}
	}

	@Test("the login limiter's 429 holds the button for a minute")
	func rateLimitedCooldown() async {
		let clock = TestClock()
		var initialState = signedOutState()
		initialState.username = "admin"
		initialState.password = "nope"
		let store = TestStore(initialState: initialState) {
			HomerConsoleReducer()
		} withDependencies: {
			$0.continuousClock = clock
			$0[HomerClient.self].login = { _, _, _ in throw HomerAPIError.rateLimited }
		}

		await store.send(.signInTapped) {
			$0.isSigningIn = true
		}
		await store.receive(\.signInFinished) {
			$0.isSigningIn = false
			$0.loginError = "Too many login attempts. Please wait a moment before trying again."
			$0.loginCooldown = 60
		}

		// Ignored while cooling down.
		await store.send(.signInTapped)

		await clock.advance(by: .seconds(1))
		await store.receive(\.loginCooldownTicked) {
			$0.loginCooldown = 59
		}
		await store.skipInFlightEffects()
	}

	@Test("a 401 on a live session goes back to the form, marked expired")
	func sessionExpiresWhilePolling() async {
		var initialState = signedInState()
		initialState.isVisible = true
		initialState.questions = [question]
		initialState.hasLoadedQuestions = true
		let store = TestStore(initialState: initialState) {
			HomerConsoleReducer()
		} withDependencies: {
			$0.continuousClock = TestClock()
			$0[HomerClient.self].processes = { _, _ in throw HomerAPIError.unauthorized }
		}

		// A filter change re-reads the processes alone, so their 401 is the only answer.
		await store.send(.statusFilterToggled(.failed)) {
			$0.statusFilter = [.failed]
		}
		await store.receive(\.processesLoaded) {
			$0.session = .signedOut
			$0.sessionExpired = true
			$0.questions = []
			$0.hasLoadedQuestions = false
		}
	}

	@Test("an answered question leaves the list and the list is re-read")
	func answerQuestion() async {
		let clock = TestClock()
		let answers = LockIsolated<[String]>([])
		var initialState = signedInState()
		initialState.questions = [question]
		initialState.hasLoadedQuestions = true
		let store = TestStore(initialState: initialState) {
			HomerConsoleReducer()
		} withDependencies: {
			$0.continuousClock = clock
			$0[HomerClient.self].answerQuestion = { _, id, answer in
				answers.withValue { $0.append("\(id)=\(answer)") }
			}
			$0[HomerClient.self].openQuestions = { _ in [] }
		}

		await store.send(.answerTapped(questionId: "q-1", answer: " Yes ")) {
			$0.answeringQuestionIDs = ["q-1"]
		}
		await store.receive(\.answerFinished) {
			$0.answeringQuestionIDs = []
			$0.questions = []
		}
		await store.receive(\.questionsLoaded)

		#expect(answers.value == ["q-1=Yes"])
		await store.skipInFlightEffects()
	}

	@Test("an answer someone else gave first is reported on the card")
	func answerConflict() async {
		let clock = TestClock()
		var initialState = signedInState()
		initialState.questions = [question]
		initialState.hasLoadedQuestions = true
		let store = TestStore(initialState: initialState) {
			HomerConsoleReducer()
		} withDependencies: {
			$0.continuousClock = clock
			$0[HomerClient.self].answerQuestion = { _, _, _ in throw HomerAPIError.conflict }
			$0[HomerClient.self].openQuestions = { _ in [question] }
		}

		await store.send(.answerTapped(questionId: "q-1", answer: "No")) {
			$0.answeringQuestionIDs = ["q-1"]
		}
		await store.receive(\.answerFinished) {
			$0.answeringQuestionIDs = []
			$0.answerErrors = ["q-1": HomerAPIError.conflict.localizedDescription]
		}
		await store.receive(\.questionsLoaded)
		await store.skipInFlightEffects()
	}

	@Test("a process opens its web console page with the session's cookies")
	func processOpensWebPage() async {
		let cookie = HTTPCookie(properties: [
			.name: "homer_session", .value: "abc", .domain: "homer.example.com", .path: "/",
		])!
		let initialState = signedInState()
		let store = TestStore(initialState: initialState) {
			HomerConsoleReducer()
		} withDependencies: {
			$0[HomerClient.self].sessionCookies = { _ in [cookie] }
		}

		await store.send(.processTapped(processId: 42))
		await store.receive(\.openWebConsoleTapped) {
			$0.webPage = HomerWebPage(
				url: URL(string: "https://homer.example.com/processes/42")!,
				title: "Process #42",
				cookies: [cookie]
			)
		}
	}
}

