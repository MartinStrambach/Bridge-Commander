import ComposableArchitecture
import Foundation
import GitCore
import GitHosting
import Settings
import Testing
import ToolsIntegration
@testable import RepositoryFeature

// The create-worktree dialog's ticket and PR/MR sources: what gets searched or listed, what a
// pick turns into (branch name, Claude prompt), and what is finally handed to the creator.
@Suite("Create worktree dialog: ticket and PR/MR sources")
@MainActor
struct CreateWorktreeSourceTests {
	private let repo = "/repos/app"
	private let ticket = YouTrackIssueSummary(id: "MOB-42", summary: "Fix login crash")

	// MARK: - Ticket

	@Test("the ticket source is offered only when the group has a YouTrack instance")
	func ticketSourceNeedsYouTrack() {
		#expect(CreateWorktreeButtonReducer.State(repositoryPath: repo).availableSources == [.branch, .pullRequest])
		#expect(makeState(youtrack: true).availableSources == [.branch, .ticket, .newTicket, .pullRequest])
	}

	@Test("switching to the ticket source lists the user's open tickets right away")
	func switchingToTicketsSearches() async {
		let store = makeStore(searchResults: [ticket])

		await store.send(.sourceChanged(.ticket)) {
			$0.source = .ticket
			$0.isSearchingTickets = true
		}
		await store.receive(\.ticketsLoaded) {
			$0.isSearchingTickets = false
			$0.tickets = [self.ticket]
		}
	}

	@Test("typing searches once the user pauses, with the final text only")
	func typingIsDebounced() async {
		let clock = TestClock()
		let queries = LockIsolated<[String]>([])
		let store = makeStore(searchResults: [ticket], clock: clock, queries: queries)
		// What is asked of YouTrack is the point here; the spinner is covered above.
		store.exhaustivity = .off
		await store.send(.sourceChanged(.ticket))
		await store.receive(\.ticketsLoaded)

		await store.send(.binding(.set(\.ticketQuery, "log")))
		await clock.advance(by: .milliseconds(100))
		await store.send(.binding(.set(\.ticketQuery, "login")))
		await clock.advance(by: CreateWorktreeButtonReducer.ticketSearchDebounce)
		await store.receive(\.ticketsLoaded)

		#expect(queries.value == ["", "login"])
	}

	@Test("an answer to a query that has since changed is dropped")
	func staleAnswerIsDropped() async {
		var state = makeState(youtrack: true)
		state.source = .ticket
		state.ticketQuery = "login"
		state.isSearchingTickets = true
		let store = TestStore(initialState: state) { CreateWorktreeButtonReducer() }

		await store.send(.ticketsLoaded(query: "log", [ticket]))
		await store.send(.ticketSearchFailed(query: "lo", "boom"))
	}

	@Test("picking a ticket names the branch after it with the template, and prefills the prompt")
	func pickingTicketNamesBranch() async {
		@Shared(.ticketBranchNameTemplate) var template = BranchNameFormatter.defaultTicketBranchTemplate
		$template.withLock { $0 = "bugfix/{summary} {ticket}" }
		var state = makeState(youtrack: true)
		state.source = .ticket
		state.tickets = [ticket]
		let store = TestStore(initialState: state) { CreateWorktreeButtonReducer() }

		await store.send(.ticketSelected("MOB-42")) {
			$0.selectedTicketId = "MOB-42"
			// The template's space is sanitized like a typed one.
			$0.branchName = "bugfix/fix_login_crash_MOB-42"
			$0.claudePrompt = "Work on YouTrack ticket MOB-42: Fix login crash (https://yt.example/issue/MOB-42)"
		}
		// The list writes its selection back on reload; that must not undo an edit.
		await store.send(.binding(.set(\.branchName, "bugfix/login_MOB-42"))) {
			$0.branchName = "bugfix/login_MOB-42"
		}
		await store.send(.ticketSelected("MOB-42"))
	}

	@Test("a ticket always gets a new branch off the chosen base")
	func ticketCreatesNewBranch() {
		var state = makeState(youtrack: true)
		state.source = .ticket
		state.tickets = [ticket]
		state.selectedTicketId = "MOB-42"
		state.branchName = "fix_login_crash_MOB-42"
		state.selectedBaseBranch = "develop"
		state.createNewBranch = false
		state.availableBranches = [BranchInfo(name: "develop", existsLocally: true, existsRemotely: true)]

		#expect(state.canCreate)
		#expect(CreateWorktreeButtonReducer().creationRequest(from: state) == .init(
			branchName: "fix_login_crash_MOB-42",
			baseBranch: "develop",
			createNewBranch: true,
			startFromOrigin: true
		))
	}

	@Test("a search that no longer includes the picked ticket drops the pick")
	func reloadDropsVanishedPick() async {
		var state = makeState(youtrack: true)
		state.source = .ticket
		state.tickets = [ticket]
		state.selectedTicketId = "MOB-42"
		state.branchName = "fix_login_crash_MOB-42"
		state.claudePrompt = "Work on it"
		state.ticketQuery = "other"
		state.isSearchingTickets = true
		let store = TestStore(initialState: state) { CreateWorktreeButtonReducer() }

		await store.send(.ticketsLoaded(query: "other", [])) {
			$0.isSearchingTickets = false
			$0.tickets = []
			$0.selectedTicketId = nil
			$0.branchName = ""
			$0.claudePrompt = ""
		}
	}

	// MARK: - Start point

	@Test("where a new branch starts is shown only when one is made, and picked only when the base has both sides")
	func startPointChoice() {
		var state = makeState(youtrack: false)
		state.availableBranches = [
			BranchInfo(name: "main", existsLocally: true, existsRemotely: true),
			BranchInfo(name: "local-only", existsLocally: true, existsRemotely: false),
			BranchInfo(name: "remote-only", existsLocally: false, existsRemotely: true)
		]
		state.selectedBaseBranch = "main"
		#expect(state.showsStartPoint)
		#expect(state.canChooseStartPoint)

		// One side only: that side, whatever was picked before.
		state.$startFromLocalBase.withLock { $0 = true }
		state.selectedBaseBranch = "remote-only"
		#expect(!state.canChooseStartPoint)
		#expect(state.startsFromOrigin)
		state.$startFromLocalBase.withLock { $0 = false }
		state.selectedBaseBranch = "local-only"
		#expect(!state.canChooseStartPoint)
		#expect(!state.startsFromOrigin)

		// Checking out the base itself makes no new branch to start anywhere.
		state.createNewBranch = false
		#expect(!state.showsStartPoint)
		state.source = .ticket
		#expect(state.showsStartPoint)
	}

	@Test("a new branch starts at origin's base unless local is picked, which is remembered")
	func startPointPick() async {
		var state = makeState(youtrack: false)
		state.availableBranches = [BranchInfo(name: "main", existsLocally: true, existsRemotely: true)]
		state.selectedBaseBranch = "main"
		state.branchName = "feature"
		#expect(CreateWorktreeButtonReducer().creationRequest(from: state)?.startFromOrigin == true)

		let store = TestStore(initialState: state) { CreateWorktreeButtonReducer() }
		await store.send(.startFromLocalBaseChanged(true)) {
			$0.$startFromLocalBase.withLock { $0 = true }
		}
		#expect(CreateWorktreeButtonReducer().creationRequest(from: store.state)?.startFromOrigin == false)
		#expect(CreateWorktreeButtonReducer.State(repositoryPath: repo).startFromLocalBase)
	}

	// MARK: - PR / MR

	@Test("a PR/MR checks out its own branch, without making a new one")
	func pullRequestChecksOutItsBranch() async {
		let pullRequest = OpenPullRequest(
			number: 7, title: "Login", sourceBranch: "login_MOB-2", author: "ms",
			url: "https://gitlab.com/g/p/-/merge_requests/7", isDraft: false, provider: .gitlab
		)
		var state = makeState(youtrack: false)
		state.source = .pullRequest
		state.pullRequests = [pullRequest]
		let store = TestStore(initialState: state) { CreateWorktreeButtonReducer() }

		await store.send(.pullRequestSelected(7)) {
			$0.selectedPullRequestNumber = 7
			$0.claudePrompt = "Continue work on MR !7: Login (https://gitlab.com/g/p/-/merge_requests/7)"
		}
		#expect(store.state.canCreate)
		#expect(CreateWorktreeButtonReducer().creationRequest(from: store.state) == .init(
			branchName: "login_MOB-2",
			baseBranch: "login_MOB-2",
			createNewBranch: false
		))
	}

	@Test("a PR from a fork is fetched from the ref origin keeps it under")
	func forkPullRequestFetchesItsHeadRef() {
		let pullRequest = OpenPullRequest(
			number: 96, title: "Resizable sidebar", sourceBranch: "feat/sidebar", author: "lm",
			url: "https://github.com/o/r/pull/96", isDraft: false, provider: .github,
			isFromFork: true, forkOwner: "lm"
		)
		var state = makeState(youtrack: false)
		state.source = .pullRequest
		state.pullRequests = [pullRequest]
		state.selectedPullRequestNumber = 96

		#expect(state.canCreate)
		#expect(CreateWorktreeButtonReducer().creationRequest(from: state) == .init(
			branchName: "feat/sidebar",
			baseBranch: "feat/sidebar",
			createNewBranch: false,
			fork: .init(headRef: "refs/pull/96/head", branchCandidates: ["feat/sidebar", "lm/feat/sidebar"])
		))
	}

	@Test("only mine narrows the list to the viewer's PRs/MRs and drops a pick it hides")
	func onlyMyPullRequests() async {
		let mine = OpenPullRequest(
			number: 7, title: "Login", sourceBranch: "login_MOB-2", author: "ms",
			url: "https://gitlab.com/g/p/-/merge_requests/7", isDraft: false, provider: .gitlab,
			isAuthoredByViewer: true
		)
		let theirs = OpenPullRequest(
			number: 8, title: "Logout", sourceBranch: "logout_MOB-3", author: "x",
			url: "https://gitlab.com/g/p/-/merge_requests/8", isDraft: false, provider: .gitlab
		)
		var state = makeState(youtrack: false)
		state.source = .pullRequest
		state.pullRequests = [mine, theirs]
		state.selectedPullRequestNumber = 8
		state.claudePrompt = "Continue work on MR !8"
		let store = TestStore(initialState: state) { CreateWorktreeButtonReducer() }
		#expect(store.state.filteredPullRequests == [mine, theirs])

		await store.send(.onlyMyPullRequestsChanged(true)) {
			$0.$onlyMyPullRequests.withLock { $0 = true }
			$0.selectedPullRequestNumber = nil
			$0.claudePrompt = ""
		}
		#expect(store.state.filteredPullRequests == [mine])

		await store.send(.onlyMyPullRequestsChanged(false)) {
			$0.$onlyMyPullRequests.withLock { $0 = false }
		}
		#expect(store.state.filteredPullRequests == [mine, theirs])
	}

	@Test("a missing token says where to add one")
	func pullRequestTokenMissing() async {
		let state = makeState(youtrack: false)
		let store = TestStore(initialState: state) {
			CreateWorktreeButtonReducer()
		} withDependencies: {
			$0[GitClient.self].getOriginRemote = { _ in GitRemote(host: "gitlab.com", owner: "g", repo: "p") }
			$0[PullRequestClient.self].listOpen = { _ in throw GitHostingError.missingToken }
		}

		await store.send(.loadPullRequests) {
			$0.isLoadingPullRequests = true
		}
		await store.receive(\.pullRequestsFailed) {
			$0.isLoadingPullRequests = false
			$0.pullRequestError = "Add a GitLab token in Settings to list open MRs."
		}
	}

	@Test("a remote on another host is reported without asking any provider")
	func pullRequestUnsupportedHost() async {
		let state = makeState(youtrack: false)
		let store = TestStore(initialState: state) {
			CreateWorktreeButtonReducer()
		} withDependencies: {
			$0[GitClient.self].getOriginRemote = { _ in GitRemote(host: "git.example.com", owner: "g", repo: "p") }
		}

		await store.send(.loadPullRequests) {
			$0.isLoadingPullRequests = true
		}
		await store.receive(\.pullRequestsFailed) {
			$0.isLoadingPullRequests = false
			$0.pullRequestError = "origin is on git.example.com; only github.com and gitlab.com are supported."
		}
	}

	@Test("typing searches the host once the user pauses; its finds follow the listed matches")
	func pullRequestRemoteSearch() async throws {
		let listed = pullRequest(7, "Login screen")
		let older = pullRequest(6407, "Country ranking error state")
		let clock = TestClock()
		let queries = LockIsolated<[OpenPullRequestQuery]>([])
		var state = makeState(youtrack: false)
		state.source = .pullRequest
		state.pullRequests = [listed]
		let store = makePullRequestStore(state: state, clock: clock, queries: queries) { query in
			query.number == 6407 ? [older] : [listed, older]
		}

		await store.send(.binding(.set(\.pullRequestFilter, "64"))) {
			$0.pullRequestFilter = "64"
			$0.isSearchingPullRequests = true
		}
		await store.send(.binding(.set(\.pullRequestFilter, "6407"))) {
			$0.pullRequestFilter = "6407"
		}
		await clock.advance(by: CreateWorktreeButtonReducer.pullRequestSearchDebounce)
		await store.receive(\.pullRequestSearchLoaded) {
			$0.isSearchingPullRequests = false
			$0.searchedPullRequests = [older]
		}
		#expect(queries.value == [OpenPullRequestQuery("6407")])
		#expect(store.state.filteredPullRequests == [older])

		await store.send(.pullRequestSelected(6407)) {
			$0.selectedPullRequestNumber = 6407
			$0.claudePrompt = CreateWorktreeButtonReducer.claudePrompt(for: older)
		}
		#expect(store.state.selectedPullRequest == older)

		// A hit the host also returns for a listed match is shown once, the listed one first.
		await store.send(.binding(.set(\.pullRequestFilter, "o"))) {
			$0.pullRequestFilter = "o"
			$0.isSearchingPullRequests = true
		}
		await clock.advance(by: CreateWorktreeButtonReducer.pullRequestSearchDebounce)
		await store.receive(\.pullRequestSearchLoaded) {
			$0.isSearchingPullRequests = false
			$0.searchedPullRequests = [listed, older]
		}
		#expect(store.state.filteredPullRequests == [listed, older])

		// Clearing the filter drops the finds, but not the pick among them.
		await store.send(.binding(.set(\.pullRequestFilter, ""))) {
			$0.pullRequestFilter = ""
			$0.isSearchingPullRequests = false
			$0.searchedPullRequests = [older]
		}
		#expect(store.state.filteredPullRequests == [listed])
		#expect(store.state.selectedPullRequest == older)
	}

	@Test("an answer to a filter that has since changed is dropped")
	func pullRequestStaleSearch() async {
		var state = makeState(youtrack: false)
		state.source = .pullRequest
		state.pullRequestFilter = "login"
		state.isSearchingPullRequests = true
		let store = TestStore(initialState: state) { CreateWorktreeButtonReducer() }

		await store.send(.pullRequestSearchLoaded(filter: "log", [pullRequest(1, "Old")]))
		await store.send(.pullRequestSearchFailed(filter: "log", "GitLab search failed: HTTP 500"))
		await store.send(.pullRequestSearchFailed(filter: "login", "GitLab search failed: HTTP 500")) {
			$0.isSearchingPullRequests = false
			$0.pullRequestSearchError = "GitLab search failed: HTTP 500"
		}
	}

	@Test("no search is sent while the listing has failed")
	func pullRequestSearchAfterFailedListing() async {
		var state = makeState(youtrack: false)
		state.source = .pullRequest
		state.pullRequestError = "Add a GitLab token in Settings to list open MRs."
		let store = TestStore(initialState: state) { CreateWorktreeButtonReducer() }

		await store.send(.binding(.set(\.pullRequestFilter, "6407"))) {
			$0.pullRequestFilter = "6407"
		}
	}

	// MARK: - Follow-up

	@Test("the follow-up becomes what the list opens once the worktree exists")
	func followUpMapsToLaunch() {
		typealias Reducer = CreateWorktreeButtonReducer
		#expect(Reducer.launch(for: .nothing, claudePrompt: "x") == nil)
		#expect(Reducer.launch(for: .openTerminal, claudePrompt: "x") == .terminal)
		#expect(Reducer.launch(for: .runClaude, claudePrompt: "") == .command("claude"))
		#expect(Reducer.launch(for: .runClaude, claudePrompt: "Work on MOB-1") == .command("claude 'Work on MOB-1'"))
	}

	@Test("switching sources forgets the previous source's pick")
	func switchingSourcesResetsPick() async {
		var state = makeState(youtrack: true)
		state.source = .ticket
		state.tickets = [ticket]
		state.selectedTicketId = "MOB-42"
		state.branchName = "fix_login_crash_MOB-42"
		state.claudePrompt = "Work on it"
		let store = TestStore(initialState: state) { CreateWorktreeButtonReducer() }

		await store.send(.sourceChanged(.branch)) {
			$0.source = .branch
			$0.selectedTicketId = nil
			$0.branchName = ""
			$0.claudePrompt = ""
		}
	}

	// MARK: - Default tab

	@Test("the dialog opens on the group's own tab over the app-wide one")
	func opensOnGroupSource() async {
		@Shared(.defaultWorktreeSource) var defaultSource = WorktreeSource.branch
		$defaultSource.withLock { $0 = .ticket }
		@Shared(.groupSettings) var groupSettings: [String: RepoGroupSettings] = [:]
		$groupSettings.withLock {
			$0[repo] = RepoGroupSettings(youtrackBaseURL: "https://yt.example", defaultWorktreeSource: .branch)
		}
		let store = TestStore(initialState: CreateWorktreeButtonReducer.State(repositoryPath: repo)) {
			CreateWorktreeButtonReducer()
		}
		store.exhaustivity = .off

		await store.send(.showDialog)
		#expect(store.state.source == .branch)
	}

	@Test("a group without a tab of its own opens on the app-wide one, every time")
	func opensOnDefaultSource() async {
		@Shared(.defaultWorktreeSource) var defaultSource = WorktreeSource.branch
		$defaultSource.withLock { $0 = .ticket }
		let store = makeStore(searchResults: [ticket])
		store.exhaustivity = .off

		await store.send(.showDialog)
		#expect(store.state.source == .ticket)

		// Switching tabs is for this opening only.
		await store.send(.sourceChanged(.branch))
		await store.send(.cancelCreation)
		await store.send(.showDialog)
		#expect(store.state.source == .ticket)
	}

	@Test("a ticket default falls back to the branch tab in a group without YouTrack")
	func ticketDefaultFallsBack() async {
		@Shared(.defaultWorktreeSource) var defaultSource = WorktreeSource.branch
		$defaultSource.withLock { $0 = .ticket }
		let state = makeState(youtrack: false)
		let store = TestStore(initialState: state) { CreateWorktreeButtonReducer() }
		store.exhaustivity = .off

		await store.send(.showDialog)
		#expect(store.state.source == .branch)
	}

	// MARK: - Helpers

	private func pullRequest(_ number: Int, _ title: String) -> OpenPullRequest {
		OpenPullRequest(
			number: number, title: title, sourceBranch: "branch-\(number)", author: "x",
			url: "https://gitlab.com/g/p/-/merge_requests/\(number)", isDraft: false, provider: .gitlab
		)
	}

	private func makePullRequestStore(
		state: CreateWorktreeButtonReducer.State,
		clock: TestClock<Duration>,
		queries: LockIsolated<[OpenPullRequestQuery]>,
		results: @escaping @Sendable (OpenPullRequestQuery) -> [OpenPullRequest]
	) -> TestStoreOf<CreateWorktreeButtonReducer> {
		TestStore(initialState: state) {
			CreateWorktreeButtonReducer()
		} withDependencies: {
			$0.continuousClock = clock
			$0[GitClient.self].getOriginRemote = { _ in GitRemote(host: "gitlab.com", owner: "g", repo: "p") }
			$0[PullRequestClient.self].searchOpen = { _, query in
				queries.withValue { $0.append(query) }
				return results(query)
			}
		}
	}

	private func makeState(youtrack: Bool) -> CreateWorktreeButtonReducer.State {
		@Shared(.groupSettings) var groupSettings: [String: RepoGroupSettings] = [:]
		$groupSettings.withLock {
			$0[repo] = RepoGroupSettings(youtrackBaseURL: youtrack ? "https://yt.example" : "")
		}
		return CreateWorktreeButtonReducer.State(repositoryPath: repo)
	}

	private func makeStore(
		searchResults: [YouTrackIssueSummary],
		clock: TestClock<Duration> = TestClock(),
		queries: LockIsolated<[String]> = LockIsolated([])
	) -> TestStoreOf<CreateWorktreeButtonReducer> {
		@Shared(.youtrackAuthToken) var token = ""
		$token.withLock { $0 = "token" }
		// Built before the store: `initialState` is evaluated inside the store's dependency scope,
		// where writing the shared settings would register as an unexpected state change.
		let state = makeState(youtrack: true)
		return TestStore(initialState: state) {
			CreateWorktreeButtonReducer()
		} withDependencies: {
			$0.continuousClock = clock
			$0[YouTrackClient.self].searchIssues = { query, baseURL, authToken in
				#expect(baseURL == "https://yt.example")
				#expect(authToken == "token")
				queries.withValue { $0.append(query) }
				return searchResults
			}
		}
	}
}
