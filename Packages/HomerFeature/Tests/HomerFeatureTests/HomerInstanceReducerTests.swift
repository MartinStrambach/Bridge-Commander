import ComposableArchitecture
import DependenciesTestSupport
import Foundation
@testable import HomerFeature
import Testing

@MainActor
@Suite("Homer instance", .dependencies)
struct HomerInstanceReducerTests {
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

	private func signedOutState() -> HomerInstanceReducer.State {
		var state = HomerInstanceReducer.State(baseURL: Self.baseURL)
		state.session = .signedOut
		return state
	}

	private func signedInState() -> HomerInstanceReducer.State {
		var state = HomerInstanceReducer.State(baseURL: Self.baseURL)
		state.session = .signedIn(admin)
		return state
	}

	@Test("a stored session that is still valid signs straight in and starts polling questions")
	func startWithLiveSession() async {
		let clock = TestClock()
		let store = TestStore(initialState: HomerInstanceReducer.State(baseURL: Self.baseURL)) {
			HomerInstanceReducer()
		} withDependencies: {
			$0.continuousClock = clock
			$0[HomerClient.self].me = { _ in admin }
			$0[HomerClient.self].openQuestions = { _ in [question] }
		}

		await store.send(.start)
		await store.receive(\.sessionChecked) {
			$0.session = .signedIn(admin)
			$0.signIn.username = "admin"
		}
		await store.receive(\.questionsLoaded) {
			$0.questions = [question]
			$0.hasLoadedQuestions = true
		}
		await store.skipInFlightEffects()

		@Shared(.homerUsernames) var usernames
		#expect(usernames == [Self.baseURL: "admin"])
	}

	@Test("the username of an earlier sign-in fills the form after a relaunch")
	func rememberedUsername() {
		@Shared(.homerUsernames) var usernames
		$usernames.withLock { $0 = [Self.baseURL: "admin"] }

		let state = HomerInstanceReducer.State(baseURL: Self.baseURL)

		#expect(state.signIn.username == "admin")
	}

	@Test("an expired cookie at launch shows the form without an error")
	func startWithExpiredCookie() async {
		let store = TestStore(initialState: HomerInstanceReducer.State(baseURL: Self.baseURL)) {
			HomerInstanceReducer()
		} withDependencies: {
			$0[HomerClient.self].me = { _ in throw HomerAPIError.unauthorized }
		}

		await store.send(.start)
		await store.receive(\.sessionChecked) {
			$0.session = .signedOut
		}
	}

	@Test("an unreachable instance at launch says why on its form")
	func startUnreachable() async {
		let store = TestStore(initialState: HomerInstanceReducer.State(baseURL: Self.baseURL)) {
			HomerInstanceReducer()
		} withDependencies: {
			$0[HomerClient.self].me = { _ in throw HomerAPIError.unreachable("offline") }
		}

		await store.send(.start)
		await store.receive(\.sessionChecked) {
			$0.session = .signedOut
			$0.signIn.loginError = HomerAPIError.unreachable("offline").localizedDescription
		}
	}

	@Test("the instance's own form signs in to its URL and starts polling")
	func signInFromOwnForm() async {
		let clock = TestClock()
		let loginArguments = LockIsolated<[String]>([])
		var initialState = signedOutState()
		initialState.signIn.username = "admin"
		initialState.signIn.password = "secret"
		let store = TestStore(initialState: initialState) {
			HomerInstanceReducer()
		} withDependencies: {
			$0.continuousClock = clock
			$0[HomerClient.self].login = { baseURL, username, password in
				loginArguments.setValue([baseURL, username, password])
				return admin
			}
			$0[HomerClient.self].openQuestions = { _ in [] }
		}

		await store.send(.signIn(.signInTapped)) {
			$0.signIn.isSigningIn = true
		}
		await store.receive(\.signIn.signInFinished) {
			$0.signIn.isSigningIn = false
			$0.signIn.password = ""
		}
		await store.receive(\.signIn.delegate.signedIn) {
			$0.session = .signedIn(admin)
		}
		await store.receive(\.questionsLoaded) {
			$0.hasLoadedQuestions = true
		}

		#expect(loginArguments.value == [Self.baseURL, "admin", "secret"])
		await store.skipInFlightEffects()
	}

	@Test("a 401 on a live session goes back to the form, marked expired")
	func sessionExpiresWhilePolling() async {
		var initialState = signedInState()
		initialState.isActive = true
		initialState.questions = [question]
		initialState.hasLoadedQuestions = true
		let store = TestStore(initialState: initialState) {
			HomerInstanceReducer()
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
			$0.signIn.sessionExpired = true
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
			HomerInstanceReducer()
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
			HomerInstanceReducer()
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

	@Test("a process opens its page natively, for the signed-in user")
	func processOpensDetail() async {
		let initialState = signedInState()
		let store = TestStore(initialState: initialState) {
			HomerInstanceReducer()
		}

		await store.send(.processTapped(processId: 42)) {
			$0.processDetail = HomerProcessDetailReducer.State(
				baseURL: Self.baseURL,
				processId: 42,
				user: admin
			)
		}
	}

	@Test("a 401 on the process page signs the instance out and closes the page")
	func processDetailUnauthorized() async {
		var initialState = signedInState()
		initialState.processDetail = HomerProcessDetailReducer.State(baseURL: Self.baseURL, processId: 42, user: admin)
		let store = TestStore(initialState: initialState) {
			HomerInstanceReducer()
		}

		await store.send(.processDetail(.presented(.delegate(.unauthorized)))) {
			$0.session = .signedOut
			$0.signIn.sessionExpired = true
			$0.processDetail = nil
		}
	}

	@Test("the process page's question count moving refreshes the instance's questions")
	func processDetailQuestionsChanged() async {
		let clock = TestClock()
		var initialState = signedInState()
		initialState.processDetail = HomerProcessDetailReducer.State(baseURL: Self.baseURL, processId: 42, user: admin)
		let store = TestStore(initialState: initialState) {
			HomerInstanceReducer()
		} withDependencies: {
			$0.continuousClock = clock
			$0[HomerClient.self].openQuestions = { _ in [] }
		}

		await store.send(.processDetail(.presented(.delegate(.questionsChanged))))
		await store.receive(\.questionsLoaded) {
			$0.hasLoadedQuestions = true
		}
		await store.skipInFlightEffects()
	}

	@Test("a tag chip filters the list and re-reads it from the top")
	func tagFilter() async {
		let clock = TestClock()
		let queries = LockIsolated<[HomerProcessQuery]>([])
		var initialState = signedInState()
		initialState.isActive = true
		initialState.processLimit = 100
		let store = TestStore(initialState: initialState) {
			HomerInstanceReducer()
		} withDependencies: {
			$0.continuousClock = clock
			$0[HomerClient.self].processes = { _, query in
				queries.withValue { $0.append(query) }
				return HomerProcessPage(processes: [], total: 0)
			}
		}

		await store.send(.tagTapped("ticket:MOB-1")) {
			$0.tagFilter = ["ticket:MOB-1"]
			$0.processLimit = 50
		}
		await store.receive(\.processesLoaded) {
			$0.hasLoadedProcesses = true
		}
		// The same tag twice adds nothing.
		await store.send(.tagTapped("ticket:MOB-1"))

		#expect(queries.value == [HomerProcessQuery(tags: ["ticket:MOB-1"], limit: 50)])
		await store.skipInFlightEffects()
	}

	@Test("a parent filter turns the root view back into a plain list")
	func parentFilterOverridesRoots() {
		var state = signedInState()
		state.rootsOnly = true
		#expect(state.showsFlowColumn)

		state.parentFilter = 7
		#expect(!state.showsFlowColumn)
		#expect(state.processQuery == HomerProcessQuery(parentProcessId: 7, limit: 50))
	}

	@Test("the root view summarizes each listed root's flow")
	func flowSummaries() async {
		let clock = TestClock()
		let root = HomerProcess(id: 1, status: .working, agentName: "factory")
		let child = HomerProcess(id: 2, status: .working, agentName: "factory-developer", openQuestions: 1, costUsd: 0.5)
		var initialState = signedInState()
		initialState.isActive = true
		initialState.rootsOnly = true
		let store = TestStore(initialState: initialState) {
			HomerInstanceReducer()
		} withDependencies: {
			$0.continuousClock = clock
			$0[HomerClient.self].processes = { _, query in
				query.rootProcessId == 1
					? HomerProcessPage(processes: [child], total: 1)
					: HomerProcessPage(processes: [root], total: 1)
			}
			$0[HomerClient.self].openQuestions = { _ in [] }
		}

		await store.send(.refreshTapped)
		store.exhaustivity = .off(showSkippedAssertions: false)
		await store.receive(\.processesLoaded) {
			$0.processes = [root]
			$0.flowSummaryRootIDs = [1]
		}
		await store.receive(\.flowSummariesLoaded) {
			$0.flowSummaries = [1: HomerFlowSummary(runCount: 1, costUsd: 0.5, state: .question, isPartial: false)]
		}
		await store.skipInFlightEffects()
	}

	@Test("killing asks first, then refreshes the list")
	func killConfirms() async {
		let clock = TestClock()
		let killed = LockIsolated<[Int]>([])
		var initialState = signedInState()
		initialState.isActive = true
		let store = TestStore(initialState: initialState) {
			HomerInstanceReducer()
		} withDependencies: {
			$0.continuousClock = clock
			$0[HomerClient.self].killProcess = { _, id in killed.withValue { $0.append(id) } }
			$0[HomerClient.self].processes = { _, _ in HomerProcessPage(processes: [], total: 0) }
		}

		store.exhaustivity = .off(showSkippedAssertions: false)
		await store.send(.killTapped(processId: 5))
		#expect(store.state.alert != nil)
		#expect(killed.value.isEmpty)

		await store.send(.alert(.presented(.killConfirmed(processId: 5)))) {
			$0.alert = nil
			$0.processActionsInFlight = [5]
		}
		await store.receive(\.processActionFinished) {
			$0.processActionsInFlight = []
		}
		await store.receive(\.processesLoaded)

		#expect(killed.value == [5])
		await store.skipInFlightEffects()
	}

	@Test("a retry opens the new run, as the console does")
	func retryOpensNewRun() async {
		let initialState = signedInState()
		let store = TestStore(initialState: initialState) {
			HomerInstanceReducer()
		} withDependencies: {
			$0[HomerClient.self].retryProcess = { _, _ in 43 }
			$0[HomerClient.self].sessionCookies = { _ in [] }
		}

		await store.send(.retryTapped(processId: 42)) {
			$0.processActionsInFlight = [42]
		}
		await store.receive(\.processActionFinished) {
			$0.processActionsInFlight = []
		}
		await store.receive(\.processTapped) {
			$0.processDetail = HomerProcessDetailReducer.State(
				baseURL: Self.baseURL,
				processId: 43,
				user: admin
			)
		}
	}

	@Test("a refused kill says why")
	func killFails() async {
		let initialState = signedInState()
		let store = TestStore(initialState: initialState) {
			HomerInstanceReducer()
		} withDependencies: {
			$0[HomerClient.self].killProcess = { _, _ in throw HomerAPIError.forbidden }
		}

		store.exhaustivity = .off(showSkippedAssertions: false)
		await store.send(.killTapped(processId: 5))
		await store.send(.alert(.presented(.killConfirmed(processId: 5))))
		await store.receive(\.processActionFinished)

		#expect(store.state.processActionsInFlight.isEmpty)
		#expect(store.state.alert?.title == TextState("Could Not Kill #5"))
	}
}
