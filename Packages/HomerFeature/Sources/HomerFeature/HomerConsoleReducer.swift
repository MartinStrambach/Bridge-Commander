import ComposableArchitecture
import Foundation

/// A page of the web console opened in the embedded browser sheet, with the session cookies it
/// needs to open signed in.
public struct HomerWebPage: Equatable, Identifiable {
	public let url: URL
	public let title: String
	let cookies: [HTTPCookie]

	public var id: URL {
		url
	}
}

/// The Homer console section: sign-in, the process list and the open questions. Everything a
/// list can't show natively (logs, artifacts, workflow graphs) opens as the web console's own
/// page in `webPage`.
@Reducer
public struct HomerConsoleReducer: Sendable {
	/// The console's own page size (`pagination.defaultLimit`).
	static let pageSize = 50
	/// The console's own refresh cadences (`polling.processListInterval`, `useQuestions`).
	static let processPollInterval: Duration = .seconds(5)
	static let questionPollInterval: Duration = .seconds(30)
	/// How long the sign-in button stays off after the login limiter answers 429, as in the
	/// console: retrying sooner only drains the bucket and prolongs the lockout.
	static let loginCooldownSeconds = 60

	public enum Tab: Equatable, Sendable {
		case processes
		case questions
	}

	public enum Session: Equatable, Sendable {
		/// Asking `/auth/me` whether the stored cookie is still a session.
		case checking
		case signedOut
		case signedIn(HomerUser)
	}

	@ObservableState
	public struct State: Equatable {
		@Shared(.homerBaseURL)
		public internal(set) var baseURL = ""
		public internal(set) var session: Session = .checking
		/// The sign-in form is shown over a live session to switch instance; cancelling it
		/// returns to that session.
		public internal(set) var isChangingInstance = false
		public var tab: Tab = .processes

		// Sign-in form
		public var endpoint = ""
		public var username = ""
		public var password = ""
		/// The endpoint field is collapsed to the instance's host behind a "Change" button, as in
		/// the console, once an instance is known.
		public internal(set) var isEditingEndpoint = false
		public internal(set) var loginError: String?
		public internal(set) var isSigningIn = false
		public internal(set) var loginCooldown = 0
		/// A session that was live ended (a call answered 401), as opposed to never having
		/// existed — the form says so, like the console's `?expired=1`.
		public internal(set) var sessionExpired = false

		// Processes
		public internal(set) var processes: IdentifiedArrayOf<HomerProcess> = []
		public internal(set) var processTotal = 0
		public internal(set) var processLimit = HomerConsoleReducer.pageSize
		public internal(set) var statusFilter: Set<HomerProcessStatus> = []
		public var rootsOnly = false
		public internal(set) var hasLoadedProcesses = false
		public internal(set) var processesError: String?

		// Questions
		public internal(set) var questions: IdentifiedArrayOf<HomerQuestion> = []
		public internal(set) var hasLoadedQuestions = false
		public internal(set) var questionsError: String?
		public internal(set) var answerDrafts: [HomerQuestion.ID: String] = [:]
		public internal(set) var answeringQuestionIDs: Set<HomerQuestion.ID> = []
		public internal(set) var answerErrors: [HomerQuestion.ID: String] = [:]

		public var webPage: HomerWebPage?

		/// Whether the section is on screen. Processes are polled only then; questions always,
		/// for the badge on the section switcher.
		var isVisible = false

		public init() {}

		public var user: HomerUser? {
			if case let .signedIn(user) = session {
				return user
			}
			return nil
		}

		public var openQuestionCount: Int {
			questions.count
		}

		public var canLoadMoreProcesses: Bool {
			processes.count < processTotal
		}

		var processQuery: HomerProcessQuery {
			HomerProcessQuery(statuses: statusFilter, rootsOnly: rootsOnly, limit: processLimit)
		}
	}

	public enum Action: BindableAction {
		case binding(BindingAction<State>)
		/// Once per launch: checks whether the stored session cookie is still valid.
		case start
		case sessionChecked(Result<HomerUser, any Error>)
		case appeared
		case disappeared

		case editEndpointTapped
		case signInTapped
		case signInFinished(baseURL: String, Result<HomerUser, any Error>)
		case loginCooldownTicked
		case changeInstanceTapped
		case cancelChangeInstanceTapped
		case signOutTapped

		case refreshTapped
		case statusFilterToggled(HomerProcessStatus)
		case statusFilterCleared
		case loadMoreProcessesTapped
		case processesLoaded(Result<HomerProcessPage, any Error>)
		case processTapped(processId: Int)

		case questionsLoaded(Result<[HomerQuestion], any Error>)
		case answerDraftChanged(questionId: HomerQuestion.ID, text: String)
		case answerTapped(questionId: HomerQuestion.ID, answer: String)
		case answerFinished(questionId: HomerQuestion.ID, Result<Void, any Error>)

		/// A page of the web console, e.g. `processes` or `processes/42`.
		case openWebConsoleTapped(path: String, title: String)
	}

	private nonisolated enum CancelID: Hashable {
		case sessionCheck
		case signIn
		case loginCooldown
		case processPolling
		case questionPolling
	}

	@Dependency(HomerClient.self)
	private var homerClient

	@Dependency(\.continuousClock)
	private var clock

	public init() {}

	public var body: some Reducer<State, Action> {
		BindingReducer()
		Reduce { state, action in
			switch action {
			case .binding(\.rootsOnly):
				state.processLimit = Self.pageSize
				return pollProcesses(state)

			case .binding(\.tab):
				// Switching to the questions shows the server's answer of now, not of up to
				// 30 s ago.
				return state.tab == .questions ? pollQuestions(state) : .none

			case .binding:
				return .none

			case .start:
				state.endpoint = state.baseURL
				guard !state.baseURL.isEmpty else {
					state.session = .signedOut
					state.isEditingEndpoint = true
					return .none
				}
				state.session = .checking
				return .run { [baseURL = state.baseURL] send in
					await send(.sessionChecked(Result { try await homerClient.me(baseURL) }))
				}
				.cancellable(id: CancelID.sessionCheck, cancelInFlight: true)

			case let .sessionChecked(.success(user)):
				state.session = .signedIn(user)
				return startPolling(state)

			case let .sessionChecked(.failure(error)):
				state.session = .signedOut
				// No cookie, or one past its 12 h, is the ordinary way to arrive here; anything
				// else (offline, wrong URL) is worth saying on the form.
				if error as? HomerAPIError != .unauthorized {
					state.loginError = error.localizedDescription
				}
				return .none

			case .appeared:
				state.isVisible = true
				guard state.user != nil else {
					return .none
				}
				return startPolling(state)

			case .disappeared:
				state.isVisible = false
				return .cancel(id: CancelID.processPolling)

			case .editEndpointTapped:
				state.isEditingEndpoint = true
				return .none

			case .signInTapped:
				guard !state.isSigningIn, state.loginCooldown == 0 else {
					return .none
				}
				let baseURL: String
				do {
					baseURL = try HomerEndpoint.normalize(state.endpoint)
				}
				catch {
					state.isEditingEndpoint = true
					state.loginError = error.localizedDescription
					return .none
				}
				let username = state.username.trimmingCharacters(in: .whitespacesAndNewlines)
				guard !username.isEmpty, !state.password.isEmpty else {
					state.loginError = "Enter your username and password."
					return .none
				}

				state.endpoint = baseURL
				state.loginError = nil
				state.isSigningIn = true
				return .run { [password = state.password] send in
					await send(.signInFinished(
						baseURL: baseURL,
						Result { try await homerClient.login(baseURL, username, password) }
					))
				}
				.cancellable(id: CancelID.signIn, cancelInFlight: true)

			case let .signInFinished(baseURL, .success(user)):
				let switchedInstance = baseURL != state.baseURL
				state.$baseURL.withLock { $0 = baseURL }
				state.isSigningIn = false
				state.password = ""
				state.sessionExpired = false
				state.isChangingInstance = false
				state.isEditingEndpoint = false
				state.session = .signedIn(user)
				if switchedInstance {
					clearData(&state)
				}
				return startPolling(state)

			case let .signInFinished(_, .failure(error)):
				state.isSigningIn = false
				switch error as? HomerAPIError {
				case .unauthorized:
					state.loginError = "Invalid credentials. Please try again."

				case .rateLimited:
					state.loginError = "Too many login attempts. Please wait a moment before trying again."
					state.loginCooldown = Self.loginCooldownSeconds
					return .run { send in
						for _ in 0 ..< Self.loginCooldownSeconds {
							try await clock.sleep(for: .seconds(1))
							await send(.loginCooldownTicked)
						}
					}
					.cancellable(id: CancelID.loginCooldown, cancelInFlight: true)

				default:
					state.loginError = error.localizedDescription
				}
				return .none

			case .loginCooldownTicked:
				state.loginCooldown = max(0, state.loginCooldown - 1)
				return .none

			case .changeInstanceTapped:
				state.isChangingInstance = true
				state.isEditingEndpoint = true
				state.endpoint = state.baseURL
				state.loginError = nil
				return .none

			case .cancelChangeInstanceTapped:
				state.isChangingInstance = false
				state.isEditingEndpoint = false
				state.endpoint = state.baseURL
				state.loginError = nil
				state.password = ""
				return .cancel(id: CancelID.signIn)

			case .signOutTapped:
				let baseURL = state.baseURL
				state.session = .signedOut
				state.sessionExpired = false
				state.isChangingInstance = false
				state.endpoint = baseURL
				clearData(&state)
				return .merge(
					stopPolling(),
					.run { _ in
						// Signing out locally does not wait on the server: the call also drops
						// the cookies, whatever the server answers.
						try? await homerClient.logout(baseURL)
					}
				)

			case .refreshTapped:
				guard state.user != nil else {
					return .none
				}
				return .merge(pollProcesses(state), pollQuestions(state))

			case let .statusFilterToggled(status):
				if state.statusFilter.contains(status) {
					state.statusFilter.remove(status)
				}
				else {
					state.statusFilter.insert(status)
				}
				state.processLimit = Self.pageSize
				return pollProcesses(state)

			case .statusFilterCleared:
				guard !state.statusFilter.isEmpty else {
					return .none
				}
				state.statusFilter = []
				state.processLimit = Self.pageSize
				return pollProcesses(state)

			case .loadMoreProcessesTapped:
				state.processLimit += Self.pageSize
				return pollProcesses(state)

			case let .processesLoaded(.success(page)):
				guard state.user != nil else {
					return .none
				}
				state.processes = IdentifiedArray(page.processes, uniquingIDsWith: { first, _ in first })
				state.processTotal = page.total
				state.hasLoadedProcesses = true
				state.processesError = nil
				return .none

			case let .processesLoaded(.failure(error)):
				guard state.user != nil else {
					return .none
				}
				if error as? HomerAPIError == .unauthorized {
					return expireSession(&state)
				}
				state.processesError = error.localizedDescription
				return .none

			case let .processTapped(processId):
				return .send(.openWebConsoleTapped(path: "processes/\(processId)", title: "Process #\(processId)"))

			case let .questionsLoaded(.success(questions)):
				guard state.user != nil else {
					return .none
				}
				state.questions = IdentifiedArray(questions, uniquingIDsWith: { first, _ in first })
				state.hasLoadedQuestions = true
				state.questionsError = nil
				// Drafts and errors of questions that closed elsewhere have nothing left to
				// belong to.
				let openIDs = Set(state.questions.ids)
				state.answerDrafts = state.answerDrafts.filter { openIDs.contains($0.key) }
				state.answerErrors = state.answerErrors.filter { openIDs.contains($0.key) }
				return .none

			case let .questionsLoaded(.failure(error)):
				guard state.user != nil else {
					return .none
				}
				if error as? HomerAPIError == .unauthorized {
					return expireSession(&state)
				}
				state.questionsError = error.localizedDescription
				return .none

			case let .answerDraftChanged(questionId, text):
				state.answerDrafts[questionId] = text
				return .none

			case let .answerTapped(questionId, answer):
				let answer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
				guard !answer.isEmpty, !state.answeringQuestionIDs.contains(questionId) else {
					return .none
				}
				state.answeringQuestionIDs.insert(questionId)
				state.answerErrors[questionId] = nil
				return .run { [baseURL = state.baseURL] send in
					await send(.answerFinished(
						questionId: questionId,
						Result { try await homerClient.answerQuestion(baseURL, questionId, answer) }
					))
				}

			case let .answerFinished(questionId, .success):
				state.answeringQuestionIDs.remove(questionId)
				state.questions.remove(id: questionId)
				state.answerDrafts[questionId] = nil
				// The answer resumes the process; its row (and open-question count) moves on.
				return .merge(pollQuestions(state), state.isVisible ? pollProcesses(state) : .none)

			case let .answerFinished(questionId, .failure(error)):
				state.answeringQuestionIDs.remove(questionId)
				if error as? HomerAPIError == .unauthorized {
					return expireSession(&state)
				}
				state.answerErrors[questionId] = error.localizedDescription
				return error as? HomerAPIError == .conflict ? pollQuestions(state) : .none

			case let .openWebConsoleTapped(path, title):
				guard let url = HomerEndpoint.pageURL(baseURL: state.baseURL, path: path) else {
					return .none
				}
				state.webPage = HomerWebPage(url: url, title: title, cookies: homerClient.sessionCookies(state.baseURL))
				return .none
			}
		}
	}

	// MARK: - Polling

	private func startPolling(_ state: State) -> Effect<Action> {
		.merge(
			pollQuestions(state),
			state.isVisible ? pollProcesses(state) : .none
		)
	}

	private func stopPolling() -> Effect<Action> {
		.merge(.cancel(id: CancelID.processPolling), .cancel(id: CancelID.questionPolling))
	}

	/// Fetches right away, then on the console's cadence. Restarting it (a filter change, "Load
	/// more") replaces the running loop, so a slow answer for the old query never lands after
	/// the new one.
	private func pollProcesses(_ state: State) -> Effect<Action> {
		.run { [baseURL = state.baseURL, query = state.processQuery] send in
			while true {
				await send(.processesLoaded(Result { try await homerClient.processes(baseURL, query) }))
				try await clock.sleep(for: Self.processPollInterval)
			}
		}
		.cancellable(id: CancelID.processPolling, cancelInFlight: true)
	}

	private func pollQuestions(_ state: State) -> Effect<Action> {
		.run { [baseURL = state.baseURL] send in
			while true {
				await send(.questionsLoaded(Result { try await homerClient.openQuestions(baseURL) }))
				try await clock.sleep(for: Self.questionPollInterval)
			}
		}
		.cancellable(id: CancelID.questionPolling, cancelInFlight: true)
	}

	/// A call answered 401 on a live session: the cookie expired or the server dropped it.
	/// Back to the sign-in form, which says why.
	private func expireSession(_ state: inout State) -> Effect<Action> {
		state.session = .signedOut
		state.sessionExpired = true
		state.isChangingInstance = false
		state.endpoint = state.baseURL
		clearData(&state)
		return stopPolling()
	}

	private func clearData(_ state: inout State) {
		state.processes = []
		state.processTotal = 0
		state.processLimit = Self.pageSize
		state.hasLoadedProcesses = false
		state.processesError = nil
		state.questions = []
		state.hasLoadedQuestions = false
		state.questionsError = nil
		state.answerDrafts = [:]
		state.answeringQuestionIDs = []
		state.answerErrors = [:]
		state.webPage = nil
	}
}
