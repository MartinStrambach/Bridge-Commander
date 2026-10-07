import ComposableArchitecture
import Foundation

/// A page of the web console opened in the embedded browser sheet, with the session cookies it
/// needs to open signed in and the instance's own web data store to open it in.
public struct HomerWebPage: Equatable, Identifiable {
	public let url: URL
	public let title: String
	let cookies: [HTTPCookie]
	let dataStoreID: UUID

	public var id: URL {
		url
	}
}

/// One Homer instance of the console section: its session, sign-in form, process list and open
/// questions. Everything a list can't show natively (logs, artifacts, workflow graphs) opens as
/// the web console's own page in `webPage`. `HomerConsoleReducer` holds one per instance, all
/// live at once: switching shows another's last data straight away.
@Reducer
public struct HomerInstanceReducer: Sendable {
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

	public enum Session: Equatable, Sendable {
		/// Asking `/auth/me` whether the stored cookie is still a session.
		case checking
		case signedOut
		case signedIn(HomerUser)
	}

	@ObservableState
	public struct State: Equatable, Identifiable {
		public let baseURL: String
		public internal(set) var session: Session = .checking
		/// Shown while signed out.
		public var signIn: HomerSignInReducer.State

		// Processes
		public internal(set) var processes: IdentifiedArrayOf<HomerProcess> = []
		public internal(set) var processTotal = 0
		public internal(set) var processLimit = HomerInstanceReducer.pageSize
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

		// The other pages
		/// The console's page, whichever instance is on screen (the console keeps it current).
		public internal(set) var page: HomerConsoleReducer.Tab = .processes
		public var continuations: HomerContinuationsReducer.State
		public var agents: HomerAgentsReducer.State
		public var costs: HomerCostsReducer.State
		/// The page reducer told it is on screen, so it polls.
		var shownChildPage: HomerChildPage?

		public var webPage: HomerWebPage?

		/// Whether this instance is the one on screen. Its processes are polled only then; the
		/// questions of every signed-in instance always, for the badges.
		var isActive = false

		public init(baseURL: String) {
			self.baseURL = baseURL
			self.signIn = HomerSignInReducer.State(baseURL: baseURL)
			self.continuations = HomerContinuationsReducer.State(baseURL: baseURL)
			self.agents = HomerAgentsReducer.State(baseURL: baseURL)
			self.costs = HomerCostsReducer.State(baseURL: baseURL)
		}

		public var id: String {
			baseURL
		}

		public var user: HomerUser? {
			if case let .signedIn(user) = session {
				return user
			}
			return nil
		}

		public var openQuestionCount: Int {
			user == nil ? 0 : questions.count
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
		/// The instance came on screen, or went off it.
		case activated
		case deactivated

		case signIn(HomerSignInReducer.Action)
		/// Signed in from elsewhere: the "Add Instance" form, given this instance's URL.
		case signedIn(HomerUser)
		case signOutTapped

		case refreshTapped
		/// The console's page changed. The questions page coming on screen shows the server's
		/// answer of now, not of up to 30 s ago.
		case pageChanged(HomerConsoleReducer.Tab)
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

		case continuations(HomerContinuationsReducer.Action)
		case agents(HomerAgentsReducer.Action)
		case costs(HomerCostsReducer.Action)

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
		Scope(\.signIn, action: \.signIn) {
			HomerSignInReducer()
		}
		Scope(\.continuations, action: \.continuations) {
			HomerContinuationsReducer()
		}
		Scope(\.agents, action: \.agents) {
			HomerAgentsReducer()
		}
		Scope(\.costs, action: \.costs) {
			HomerCostsReducer()
		}
		Reduce { state, action in
			switch action {
			case .binding(\.rootsOnly):
				// Switching views changes what a row means; a parent filter would override the
				// root view, so going there drops it, as the console does.
				if state.rootsOnly {
					state.parentFilter = nil
				}
				return refilter(&state)

			case .binding:
				return .none

			case .start:
				state.session = .checking
				return .run { [baseURL = state.baseURL] send in
					await send(.sessionChecked(Result { try await homerClient.me(baseURL) }))
				}
				.cancellable(id: CancelID.sessionCheck, cancelInFlight: true)

			case let .sessionChecked(.success(user)):
				state.session = .signedIn(user)
				return .merge(startPolling(state), syncShownChildPage(&state))

			case let .sessionChecked(.failure(error)):
				state.session = .signedOut
				// No cookie, or one past its 12 h, is the ordinary way to arrive here; anything
				// else (offline, wrong URL) is worth saying on the form.
				if error as? HomerAPIError != .unauthorized {
					state.signIn.loginError = error.localizedDescription
				}
				return .none

			case .activated:
				guard !state.isActive else {
					return .none
				}
				state.isActive = true
				guard state.user != nil else {
					return .none
				}
				return .merge(startPolling(state), syncShownChildPage(&state))

			case .deactivated:
				state.isActive = false
				return .merge(
					.cancel(id: CancelID.processPolling),
					.cancel(id: CancelID.flowSummaryPolling),
					syncShownChildPage(&state)
				)

			case let .signIn(.delegate(.signedIn(_, user))), let .signedIn(user):
				// Someone else's data (the add form signed in to this instance as another user)
				// is not this user's to see.
				let cleared = state.user?.username != user.username ? clearData(&state) : nil
				state.session = .signedIn(user)
				state.signIn.username = user.username
				state.signIn.password = ""
				state.signIn.loginError = nil
				state.signIn.sessionExpired = false
				return .merge(startPolling(state), syncShownChildPage(&state, hidingFirst: cleared))

			case .signIn:
				return .none

			case let .pageChanged(page):
				state.page = page
				let questions = page == .questions && state.user != nil ? pollQuestions(state) : .none
				return .merge(questions, syncShownChildPage(&state))

			case .signOutTapped:
				let baseURL = state.baseURL
				state.session = .signedOut
				state.signIn.sessionExpired = false
				return .merge(
					hide(clearData(&state)),
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
				let refresh = state.isActive ? pollProcesses(state) : .none
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
				return .merge(pollQuestions(state), state.isActive ? pollProcesses(state) : .none)

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
				state.webPage = HomerWebPage(
					url: url,
					title: title,
					cookies: homerClient.sessionCookies(state.baseURL),
					dataStoreID: HomerEndpoint.webDataStoreID(baseURL: state.baseURL)
				)
				return .none

			case .continuations(.delegate(let delegate)),
			     .agents(.delegate(let delegate)),
			     .costs(.delegate(let delegate)):
				switch delegate {
				case .unauthorized:
					guard state.user != nil else {
						return .none
					}
					return expireSession(&state)
				case let .openWebConsole(path, title):
					return .send(.openWebConsoleTapped(path: path, title: title))
				}

			case .continuations, .agents, .costs:
				return .none
			}
		}
		.ifLet(\.$alert, action: \.alert)
	}

	// MARK: - Polling

	private func startPolling(_ state: State) -> Effect<Action> {
		.merge(
			pollQuestions(state),
			state.isActive ? pollProcesses(state) : .none,
			state.isActive && state.agentNames.isEmpty ? loadAgentNames(state) : .none
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
		state.signIn.sessionExpired = true
		return .merge(hide(clearData(&state)), stopPolling())
	}

	// MARK: - Page reducers

	/// Tells the page reducers which of them is on screen: the one the console's page names,
	/// while this instance is on screen and signed in. The admin-only pages stay hidden for
	/// anyone else — the console offers them only to admins. `hidingFirst` is a page whose
	/// state was just replaced and whose poll must stop before anything is shown again.
	private func syncShownChildPage(
		_ state: inout State,
		hidingFirst hiddenPage: HomerChildPage? = nil
	) -> Effect<Action> {
		let page: HomerChildPage? = if let user = state.user, state.isActive,
			!state.page.isAdminOnly || user.isAdmin
		{
			HomerChildPage(state.page)
		}
		else {
			nil
		}
		var events = hiddenPage.map { [ChildPageEvent(page: $0, isShown: false)] } ?? []
		if page != state.shownChildPage {
			if let previous = state.shownChildPage {
				events.append(ChildPageEvent(page: previous, isShown: false))
			}
			state.shownChildPage = page
			if let page {
				events.append(ChildPageEvent(page: page, isShown: true))
			}
		}
		return send(events)
	}

	private func hide(_ page: HomerChildPage?) -> Effect<Action> {
		send(page.map { [ChildPageEvent(page: $0, isShown: false)] } ?? [])
	}

	private struct ChildPageEvent: Sendable {
		let page: HomerChildPage
		let isShown: Bool
	}

	/// In order, from one effect: a page hidden and shown again (another user signed in) must
	/// stop its old poll before it starts the new one.
	private func send(_ events: [ChildPageEvent]) -> Effect<Action> {
		guard !events.isEmpty else {
			return .none
		}
		return .run { send in
			for event in events {
				switch (event.page, event.isShown) {
				case (.continuations, true):
					await send(.continuations(.shown))
				case (.continuations, false):
					await send(.continuations(.hidden))
				case (.agents, true):
					await send(.agents(.shown))
				case (.agents, false):
					await send(.agents(.hidden))
				case (.costs, true):
					await send(.costs(.shown))
				case (.costs, false):
					await send(.costs(.hidden))
				}
			}
		}
	}

	/// Drops everything the signed-in user saw, and returns the page reducer that was on
	/// screen: its poll is still running, and the caller hides it.
	private func clearData(_ state: inout State) -> HomerChildPage? {
		let shownChildPage = state.shownChildPage
		state.shownChildPage = nil
		state.continuations = HomerContinuationsReducer.State(baseURL: state.baseURL)
		state.agents = HomerAgentsReducer.State(baseURL: state.baseURL)
		state.costs = HomerCostsReducer.State(baseURL: state.baseURL)
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
		return shownChildPage
	}
}
