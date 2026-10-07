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
	/// The console's Flow cells refresh on this cadence too (`useFlowSummary`).
	static let flowSummaryPollInterval: Duration = .seconds(30)
	/// Root rows whose Flow cell is summarized, in list order. Each cell is one request, so the
	/// count is bounded rather than growing with "Load more" — the console caps it the same.
	static let flowSummaryRowLimit = 20
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
		public internal(set) var agentFilter: String?
		/// Runs must carry every tag listed; a tag chip in a row adds itself.
		public internal(set) var tagFilter: [String] = []
		/// The direct children of one run. Overrides `rootsOnly`, as in the console: a run's
		/// children are never roots.
		public internal(set) var parentFilter: Int?
		public internal(set) var oldestFirst = false
		/// The agent filter's choices.
		public internal(set) var agentNames: [String] = []
		public internal(set) var hasLoadedProcesses = false
		public internal(set) var processesError: String?
		public internal(set) var flowSummaries: [HomerProcess.ID: HomerFlowSummary] = [:]
		/// The roots `flowSummaries` covers: the first rows of the root view.
		var flowSummaryRootIDs: [HomerProcess.ID] = []
		/// Kill or retry requests still waiting on the server.
		public internal(set) var processActionsInFlight: Set<HomerProcess.ID> = []
		@Presents
		public var alert: AlertState<Action.Alert>?

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

		/// The root view shows a Flow column; a parent filter turns it back into a plain list.
		public var showsFlowColumn: Bool {
			rootsOnly && parentFilter == nil
		}

		public var hasActiveFilters: Bool {
			!statusFilter.isEmpty || agentFilter != nil || !tagFilter.isEmpty || parentFilter != nil
		}

		/// What the listed runs cost together — the rows shown, not every match, as in the
		/// console's "Total cost".
		public var listedCostUsd: Double {
			processes.reduce(0) { $0 + ($1.costUsd ?? 0) }
		}

		var processQuery: HomerProcessQuery {
			HomerProcessQuery(
				statuses: statusFilter,
				rootsOnly: showsFlowColumn,
				agentName: agentFilter,
				tags: tagFilter,
				parentProcessId: parentFilter,
				oldestFirst: oldestFirst,
				limit: processLimit
			)
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
		case agentFilterChanged(String?)
		case tagTapped(String)
		case tagFilterRemoved(String)
		case showChildRunsTapped(processId: Int)
		case parentFilterCleared
		case filtersCleared
		case sortOrderToggled
		case loadMoreProcessesTapped
		case processesLoaded(Result<HomerProcessPage, any Error>)
		case agentNamesLoaded(Result<[String], any Error>)
		case flowSummariesLoaded([HomerProcess.ID: HomerFlowSummary])
		case processTapped(processId: Int)
		case killTapped(processId: Int)
		case retryTapped(processId: Int)
		case processActionFinished(processId: Int, ProcessAction, Result<Int?, any Error>)
		case alert(PresentationAction<Alert>)

		case questionsLoaded(Result<[HomerQuestion], any Error>)
		case answerDraftChanged(questionId: HomerQuestion.ID, text: String)
		case answerTapped(questionId: HomerQuestion.ID, answer: String)
		case answerFinished(questionId: HomerQuestion.ID, Result<Void, any Error>)

		/// A page of the web console, e.g. `processes` or `processes/42`.
		case openWebConsoleTapped(path: String, title: String)

		public enum ProcessAction: Equatable, Sendable {
			case kill
			case retry
		}

		public enum Alert: Equatable, Sendable {
			case killConfirmed(processId: Int)
		}
	}

	private nonisolated enum CancelID: Hashable {
		case sessionCheck
		case signIn
		case loginCooldown
		case processPolling
		case questionPolling
		case flowSummaryPolling
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
				// Switching views changes what a row means; a parent filter would override the
				// root view, so going there drops it, as the console does.
				if state.rootsOnly {
					state.parentFilter = nil
				}
				return refilter(&state)

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
				return .merge(.cancel(id: CancelID.processPolling), .cancel(id: CancelID.flowSummaryPolling))

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
				return refilter(&state)

			case let .agentFilterChanged(agentName):
				guard agentName != state.agentFilter else {
					return .none
				}
				state.agentFilter = agentName
				return refilter(&state)

			case let .tagTapped(tag):
				guard !state.tagFilter.contains(tag) else {
					return .none
				}
				state.tagFilter.append(tag)
				return refilter(&state)

			case let .tagFilterRemoved(tag):
				state.tagFilter.removeAll { $0 == tag }
				return refilter(&state)

			case let .showChildRunsTapped(processId):
				state.parentFilter = processId
				return refilter(&state)

			case .parentFilterCleared:
				state.parentFilter = nil
				return refilter(&state)

			case .filtersCleared:
				guard state.hasActiveFilters else {
					return .none
				}
				state.statusFilter = []
				state.agentFilter = nil
				state.tagFilter = []
				state.parentFilter = nil
				return refilter(&state)

			case .sortOrderToggled:
				state.oldestFirst.toggle()
				return refilter(&state)

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
				return syncFlowSummaries(&state)

			case let .processesLoaded(.failure(error)):
				guard state.user != nil else {
					return .none
				}
				if error as? HomerAPIError == .unauthorized {
					return expireSession(&state)
				}
				state.processesError = error.localizedDescription
				return .none

			case let .agentNamesLoaded(.success(names)):
				state.agentNames = names
				return .none

			case .agentNamesLoaded(.failure):
				// The filter just offers no choices; the list itself still loads.
				return .none

			case let .flowSummariesLoaded(summaries):
				let shown = Set(state.flowSummaryRootIDs)
				state.flowSummaries.merge(summaries.filter { shown.contains($0.key) }) { _, new in new }
				return .none

			case let .killTapped(processId):
				state.alert = AlertState {
					TextState("Kill process #\(processId)?")
				} actions: {
					ButtonState(role: .destructive, action: .killConfirmed(processId: processId)) {
						TextState("Kill Process")
					}
					ButtonState(role: .cancel) {
						TextState("Cancel")
					}
				} message: {
					TextState("This cannot be undone.")
				}
				return .none

			case let .alert(.presented(.killConfirmed(processId))):
				guard state.processActionsInFlight.insert(processId).inserted else {
					return .none
				}
				return .run { [baseURL = state.baseURL] send in
					await send(.processActionFinished(processId: processId, .kill, Result {
						try await homerClient.killProcess(baseURL, processId)
						return nil
					}))
				}

			case .alert:
				return .none

			case let .retryTapped(processId):
				guard state.processActionsInFlight.insert(processId).inserted else {
					return .none
				}
				return .run { [baseURL = state.baseURL] send in
					await send(.processActionFinished(processId: processId, .retry, Result {
						try await homerClient.retryProcess(baseURL, processId)
					}))
				}

			case let .processActionFinished(processId, _, .success(newProcessId)):
				state.processActionsInFlight.remove(processId)
				let refresh = state.isVisible ? pollProcesses(state) : .none
				guard let newProcessId else {
					return refresh
				}
				// The console takes you to the new run after a retry.
				return .merge(refresh, .send(.processTapped(processId: newProcessId)))

			case let .processActionFinished(processId, action, .failure(error)):
				state.processActionsInFlight.remove(processId)
				if error as? HomerAPIError == .unauthorized {
					return expireSession(&state)
				}
				state.alert = AlertState {
					TextState(action == .kill ? "Could Not Kill #\(processId)" : "Could Not Retry #\(processId)")
				} actions: {
					ButtonState(role: .cancel) {
						TextState("OK")
					}
				} message: {
					TextState(error.localizedDescription)
				}
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
		.ifLet(\.$alert, action: \.alert)
	}

	// MARK: - Polling

	private func startPolling(_ state: State) -> Effect<Action> {
		.merge(
			pollQuestions(state),
			state.isVisible ? pollProcesses(state) : .none,
			state.isVisible && state.agentNames.isEmpty ? loadAgentNames(state) : .none
		)
	}

	private func stopPolling() -> Effect<Action> {
		.merge(
			.cancel(id: CancelID.processPolling),
			.cancel(id: CancelID.questionPolling),
			.cancel(id: CancelID.flowSummaryPolling)
		)
	}

	/// A filter changed: the list restarts from its first page.
	private func refilter(_ state: inout State) -> Effect<Action> {
		state.processLimit = Self.pageSize
		return pollProcesses(state)
	}

	private func loadAgentNames(_ state: State) -> Effect<Action> {
		.run { [baseURL = state.baseURL] send in
			await send(.agentNamesLoaded(Result { try await homerClient.agentNames(baseURL) }))
		}
	}

	/// Keeps the Flow cells' summaries in step with the rows on screen: a new set of top roots
	/// restarts their poll, leaving the root view stops it.
	private func syncFlowSummaries(_ state: inout State) -> Effect<Action> {
		let rootIDs = state.showsFlowColumn
			? Array(state.processes.ids.prefix(Self.flowSummaryRowLimit))
			: []
		guard rootIDs != state.flowSummaryRootIDs else {
			return .none
		}
		state.flowSummaryRootIDs = rootIDs
		let shown = Set(rootIDs)
		state.flowSummaries = state.flowSummaries.filter { shown.contains($0.key) }
		guard !rootIDs.isEmpty else {
			return .cancel(id: CancelID.flowSummaryPolling)
		}
		return .run { [baseURL = state.baseURL] send in
			while true {
				let summaries = await withTaskGroup(of: (Int, HomerFlowSummary?).self) { group in
					for rootID in rootIDs {
						group.addTask {
							let query = HomerProcessQuery(rootProcessId: rootID, limit: HomerFlowSummary.fetchLimit)
							// A cell whose summary fails keeps its last one, or a dash.
							let page = try? await homerClient.processes(baseURL, query)
							return (rootID, page.map(HomerFlowSummary.init(page:)))
						}
					}
					var summaries: [Int: HomerFlowSummary] = [:]
					for await (rootID, summary) in group {
						summaries[rootID] = summary
					}
					return summaries
				}
				await send(.flowSummariesLoaded(summaries))
				try await clock.sleep(for: Self.flowSummaryPollInterval)
			}
		}
		.cancellable(id: CancelID.flowSummaryPolling, cancelInFlight: true)
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
		state.flowSummaries = [:]
		state.flowSummaryRootIDs = []
		state.processActionsInFlight = []
		state.agentNames = []
		state.agentFilter = nil
		state.tagFilter = []
		state.parentFilter = nil
		state.alert = nil
		state.questions = []
		state.hasLoadedQuestions = false
		state.questionsError = nil
		state.answerDrafts = [:]
		state.answeringQuestionIDs = []
		state.answerErrors = [:]
		state.webPage = nil
	}
}
