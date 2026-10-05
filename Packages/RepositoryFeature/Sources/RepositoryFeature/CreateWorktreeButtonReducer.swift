import ComposableArchitecture
import Foundation
import GitCore
import GitHosting
import Settings
import ToolsIntegration

/// How the list opens a worktree in the built-in terminal once it has been created and scanned.
enum WorktreeTerminalLaunch: Equatable, Sendable {
	/// A first tab running the group's usual startup command.
	case terminal
	/// A first tab running this command instead.
	case command(String)

	/// What replaces the group's startup command, or nil to keep it.
	var startupCommandOverride: String? {
		switch self {
		case .terminal: nil
		case let .command(command): command
		}
	}
}

@Reducer
struct CreateWorktreeButtonReducer {
	@ObservableState
	struct State: Equatable {
		let repositoryPath: String
		@Shared(.worktreeBasePath)
		var worktreeBasePath = "../worktrees"
		@Shared(.groupSettings)
		var groupSettings: [String: RepoGroupSettings] = [:]
		@Shared(.ticketBranchNameTemplate)
		var ticketBranchNameTemplate = BranchNameFormatter.defaultTicketBranchTemplate
		@Shared(.worktreeCreationFollowUp)
		var followUp = WorktreeCreationFollowUp.nothing
		/// The app-wide tab, used only where the group has not picked one of its own.
		@Shared(.defaultWorktreeSource)
		var legacyDefaultSource = WorktreeSource.branch
		var isCreating: Bool = false
		var showCreateDialog: Bool = false
		/// Reset to the group's `defaultWorktreeSource` (Settings) each time the dialog opens.
		var source: WorktreeSource = .branch
		var branchName: String = ""
		var availableBranches: [BranchInfo] = []
		var selectedBaseBranch: String = "master"
		var branchSearchText: String = ""
		var isLoadingBranches: Bool = false

		var ticketQuery: String = ""
		var tickets: [YouTrackIssueSummary] = []
		var isSearchingTickets = false
		var ticketSearchError: String?
		var selectedTicketId: String?

		var pullRequests: [OpenPullRequest] = []
		var pullRequestFilter: String = ""
		var isLoadingPullRequests = false
		var pullRequestError: String?
		var selectedPullRequestNumber: Int?

		/// Typed after `claude` when the follow-up runs Claude; blank starts it without a prompt.
		/// Prefilled from the picked ticket or PR.
		var claudePrompt: String = ""

		var repositoryName: String {
			URL(fileURLWithPath: repositoryPath).lastPathComponent
		}

		var filteredBranches: [BranchInfo] {
			guard !branchSearchText.isEmpty else { return availableBranches }
			return availableBranches.filter {
				$0.name == selectedBaseBranch ||
				$0.name.localizedCaseInsensitiveContains(branchSearchText)
			}
		}

		/// The group's YouTrack instance, or empty when the integration is off.
		var youtrackBaseURL: String {
			YouTrackURLBuilder.normalizedBase(groupSettings[repositoryPath]?.youtrackBaseURL ?? "")
		}

		var availableSources: [WorktreeSource] {
			(groupSettings[repositoryPath] ?? RepoGroupSettings()).worktreeSources
		}

		var selectedTicket: YouTrackIssueSummary? {
			selectedTicketId.flatMap { id in tickets.first { $0.id == id } }
		}

		var filteredPullRequests: [OpenPullRequest] {
			let filter = pullRequestFilter.trimmingCharacters(in: .whitespaces)
			guard !filter.isEmpty else { return pullRequests }
			return pullRequests.filter {
				$0.title.localizedCaseInsensitiveContains(filter)
					|| $0.sourceBranch.localizedCaseInsensitiveContains(filter)
					|| $0.reference.contains(filter)
					|| ($0.author?.localizedCaseInsensitiveContains(filter) ?? false)
			}
		}

		var selectedPullRequest: OpenPullRequest? {
			selectedPullRequestNumber.flatMap { number in pullRequests.first { $0.number == number } }
		}

		var canCreate: Bool {
			switch source {
			case .branch:
				!availableBranches.isEmpty && (!createNewBranch || !branchName.isEmpty)
			case .ticket:
				!availableBranches.isEmpty && selectedTicket != nil && !branchName.isEmpty
			case .pullRequest:
				selectedPullRequest != nil
			}
		}

		var createNewBranch: Bool = true
		@Presents
		var errorAlert: AlertState<Action.ErrorAlert>?
	}

	enum Action: BindableAction {
		case binding(BindingAction<State>)
		case showDialog
		case cancelCreation
		case confirmCreation
		case errorAlert(PresentationAction<ErrorAlert>)
		case didCreateSuccessfully(
			copyResult: WorktreeFileCopier.Result?,
			worktreePath: String,
			launch: WorktreeTerminalLaunch?
		)
		case didFailWithError(String)
		case loadBranches
		case branchesLoaded([BranchInfo])
		case sourceChanged(WorktreeSource)
		case followUpChanged(WorktreeCreationFollowUp)
		case searchTickets
		case ticketsLoaded(query: String, [YouTrackIssueSummary])
		case ticketSearchFailed(query: String, String)
		case ticketSelected(String?)
		case loadPullRequests
		case pullRequestsLoaded([OpenPullRequest])
		case pullRequestsFailed(String)
		case pullRequestSelected(Int?)

		enum ErrorAlert: Equatable {}
	}

	private enum CancelID {
		case ticketSearch
		case pullRequests
	}

	/// Typing pauses this long before YouTrack is asked, so a search is not sent per keystroke.
	static let ticketSearchDebounce = Duration.milliseconds(300)

	@Dependency(YouTrackClient.self)
	private var youTrackClient

	@Dependency(PullRequestClient.self)
	private var pullRequestClient

	@Dependency(GitClient.self)
	private var gitClient

	@Dependency(\.continuousClock)
	private var clock

	var body: some Reducer<State, Action> {
		BindingReducer()
		Reduce { state, action in
			switch action {
			case .binding(\.branchName):
				// Git rejects whitespace in ref names; swap it for underscores as the user types
				// so the field always shows the name that will actually be created.
				state.branchName = GitBranchNameSanitizer.sanitize(state.branchName)
				return .none

			case .binding(\.ticketQuery):
				return searchTickets(in: &state, debounce: true)

			case .showDialog:
				state.showCreateDialog = true
				state.branchName = ""
				state.claudePrompt = ""
				state.source = (state.groupSettings[state.repositoryPath] ?? RepoGroupSettings())
					.openingWorktreeSource(fallback: state.legacyDefaultSource)
				return .merge(.send(.loadBranches), loadSourceItems(for: state.source, in: &state))

			case .loadBranches:
				state.isLoadingBranches = true
				return .run { [path = state.repositoryPath] send in
					let branches = await GitBranchListHelper.listBranchesWithInfo(at: path)
					await send(.branchesLoaded(branches))
				}

			case let .branchesLoaded(branches):
				state.availableBranches = branches
				state.isLoadingBranches = false
				// Pre-select the per-group default branch, falling back to master/main.
				let configured = state.groupSettings[state.repositoryPath]?.defaultBranch ?? ""
				if let resolved = DefaultBranchResolver.resolveBaseBranch(
					configured: configured,
					available: branches.map(\.name)
				) {
					state.selectedBaseBranch = resolved
				}
				return .none

			case let .sourceChanged(source):
				guard state.availableSources.contains(source), source != state.source else {
					return .none
				}
				state.source = source
				// The branch name and prompt belong to whatever was picked in the source just
				// left; carrying them over would create the previous ticket's branch.
				state.branchName = ""
				state.claudePrompt = ""
				state.selectedTicketId = nil
				state.selectedPullRequestNumber = nil
				return loadSourceItems(for: source, in: &state)

			case let .followUpChanged(followUp):
				state.$followUp.withLock { $0 = followUp }
				return .none

			case .searchTickets:
				return searchTickets(in: &state, debounce: false)

			case let .ticketsLoaded(query, tickets):
				// A slower answer to an older query must not replace the current one's.
				guard query == state.ticketQuery else {
					return .none
				}
				state.isSearchingTickets = false
				state.ticketSearchError = nil
				state.tickets = tickets
				if let selected = state.selectedTicketId, !tickets.contains(where: { $0.id == selected }) {
					state.selectedTicketId = nil
					state.branchName = ""
					state.claudePrompt = ""
				}
				return .none

			case let .ticketSearchFailed(query, message):
				guard query == state.ticketQuery else {
					return .none
				}
				state.isSearchingTickets = false
				state.ticketSearchError = message
				state.tickets = []
				return .none

			case let .ticketSelected(ticketId):
				// The list writes its selection back on reload; re-selecting the same ticket must
				// not throw away an edited branch name.
				guard ticketId != state.selectedTicketId else {
					return .none
				}
				state.selectedTicketId = ticketId
				guard let ticket = state.selectedTicket else {
					state.branchName = ""
					state.claudePrompt = ""
					return .none
				}
				state.branchName = GitBranchNameSanitizer.sanitize(
					BranchNameFormatter.branchName(
						ticketId: ticket.id,
						summary: ticket.summary,
						template: state.ticketBranchNameTemplate
					)
				)
				state.claudePrompt = Self.claudePrompt(for: ticket, baseURL: state.youtrackBaseURL)
				return .none

			case .loadPullRequests:
				state.isLoadingPullRequests = true
				state.pullRequestError = nil
				return .run { [path = state.repositoryPath] send in
					guard let remote = await gitClient.getOriginRemote(at: path) else {
						await send(.pullRequestsFailed("This repository has no origin remote."))
						return
					}
					guard ["github.com", "gitlab.com"].contains(remote.host.lowercased()) else {
						await send(.pullRequestsFailed("origin is on \(remote.host); only github.com and gitlab.com are supported."))
						return
					}
					do {
						await send(.pullRequestsLoaded(try await pullRequestClient.listOpen(remote: remote)))
					}
					catch {
						await send(.pullRequestsFailed(Self.pullRequestErrorMessage(for: error, host: remote.host)))
					}
				}
				.cancellable(id: CancelID.pullRequests, cancelInFlight: true)

			case let .pullRequestsLoaded(pullRequests):
				state.isLoadingPullRequests = false
				state.pullRequestError = nil
				state.pullRequests = pullRequests
				if let selected = state.selectedPullRequestNumber,
				   !pullRequests.contains(where: { $0.number == selected }) {
					state.selectedPullRequestNumber = nil
					state.claudePrompt = ""
				}
				return .none

			case let .pullRequestsFailed(message):
				state.isLoadingPullRequests = false
				state.pullRequestError = message
				state.pullRequests = []
				return .none

			case let .pullRequestSelected(number):
				guard number != state.selectedPullRequestNumber else {
					return .none
				}
				state.selectedPullRequestNumber = number
				state.claudePrompt = state.selectedPullRequest.map(Self.claudePrompt(for:)) ?? ""
				return .none

			case .cancelCreation:
				state.showCreateDialog = false
				resetDialog(&state)
				return .merge(.cancel(id: CancelID.ticketSearch), .cancel(id: CancelID.pullRequests))

			case .confirmCreation:
				guard state.canCreate, let request = creationRequest(from: state) else {
					return .none
				}

				state.showCreateDialog = false
				state.isCreating = true
				let copyPaths = state.groupSettings[state.repositoryPath]?.worktreeCopyPaths ?? []
				let launch = Self.launch(for: state.followUp, claudePrompt: state.claudePrompt)
				return .run { [
					request,
					path = state.repositoryPath,
					worktreeBasePath = state.worktreeBasePath,
					copyPaths,
					launch
				] send in
					do {
						let worktreeURL = try await GitWorktreeCreator.createWorktree(
							branchName: request.branchName,
							baseBranch: request.baseBranch,
							repositoryPath: path,
							createNewBranch: request.createNewBranch,
							worktreeBasePath: worktreeBasePath
						)
						let copyResult: WorktreeFileCopier.Result? = copyPaths.isEmpty
							? nil
							: WorktreeFileCopier.copy(
								paths: copyPaths,
								from: URL(fileURLWithPath: path),
								to: worktreeURL
							)
						await send(.didCreateSuccessfully(
							copyResult: copyResult,
							worktreePath: worktreeURL.path,
							launch: launch
						))
					}
					catch {
						await send(.didFailWithError(error.localizedDescription))
					}
				}

			case let .didCreateSuccessfully(copyResult, _, _):
				state.isCreating = false
				resetDialog(&state)
				if let result = copyResult, result.hasWarnings {
					var lines: [String] = []
					if !result.missing.isEmpty {
						lines.append("Missing in source repository:")
						lines.append(contentsOf: result.missing.map { "  • \($0)" })
					}
					if !result.failed.isEmpty {
						if !lines.isEmpty { lines.append("") }
						lines.append("Failed to copy:")
						lines.append(contentsOf: result.failed.map { "  • \($0.path) — \($0.reason)" })
					}
					state.errorAlert = AlertState {
						TextState("Worktree created with warnings")
					} actions: {
						ButtonState(role: .cancel) {
							TextState("OK")
						}
					} message: {
						TextState(lines.joined(separator: "\n"))
					}
				}
				return .none

			case let .didFailWithError(error):
				state.isCreating = false
				state.errorAlert = AlertState {
					TextState("Creation Error")
				} actions: {
					ButtonState(role: .cancel) {
						TextState("OK")
					}
				} message: {
					TextState(error)
				}
				return .none

			case .errorAlert:
				return .none

			default:
				return .none
			}
		}
		.ifLet(\.$errorAlert, action: \.errorAlert)
	}

	// MARK: - Helpers

	/// The arguments `GitWorktreeCreator` gets for the dialog's current source.
	struct CreationRequest: Equatable, Sendable {
		let branchName: String
		let baseBranch: String
		let createNewBranch: Bool
	}

	func creationRequest(from state: State) -> CreationRequest? {
		switch state.source {
		case .branch, .ticket:
			let branchName = GitBranchNameSanitizer.sanitize(state.branchName)
			// A ticket always gets a branch of its own; only the plain source may check out
			// the base branch as it is.
			let createNewBranch = state.source == .ticket || state.createNewBranch
			guard !createNewBranch || !branchName.isEmpty else {
				return nil
			}
			return CreationRequest(
				branchName: branchName,
				baseBranch: state.selectedBaseBranch,
				createNewBranch: createNewBranch
			)

		case .pullRequest:
			// The PR's branch is checked out as is — creating a new one off it would leave the
			// worktree's commits outside the PR. The creator makes a local tracking branch when
			// only origin has it.
			guard let pullRequest = state.selectedPullRequest else {
				return nil
			}
			return CreationRequest(
				branchName: pullRequest.sourceBranch,
				baseBranch: pullRequest.sourceBranch,
				createNewBranch: false
			)
		}
	}

	/// Starts the list the source picks from, unless it is already loaded or loading.
	private func loadSourceItems(for source: WorktreeSource, in state: inout State) -> Effect<Action> {
		switch source {
		case .branch:
			return .none
		case .ticket:
			// Always re-run: the user's open tickets change between openings of the dialog.
			return searchTickets(in: &state, debounce: false)
		case .pullRequest:
			guard !state.isLoadingPullRequests else {
				return .none
			}
			return .send(.loadPullRequests)
		}
	}

	/// Searches YouTrack for the current query. The spinner shows from the keystroke on, debounce
	/// included, so the list never looks settled while a newer answer is still coming.
	private func searchTickets(in state: inout State, debounce: Bool) -> Effect<Action> {
		let baseURL = state.youtrackBaseURL
		guard !baseURL.isEmpty else {
			return .none
		}
		let query = state.ticketQuery
		state.isSearchingTickets = true
		@Shared(.youtrackAuthToken)
		var authToken = ""

		return .run { [authToken, clock, youTrackClient] send in
			if debounce {
				try await clock.sleep(for: Self.ticketSearchDebounce)
			}
			do {
				let tickets = try await youTrackClient.searchIssues(
					query: query,
					baseURL: baseURL,
					authToken: authToken.trimmingCharacters(in: .whitespacesAndNewlines)
				)
				await send(.ticketsLoaded(query: query, tickets))
			}
			catch is CancellationError {}
			catch {
				await send(.ticketSearchFailed(query: query, Self.ticketErrorMessage(for: error)))
			}
		}
		.cancellable(id: CancelID.ticketSearch, cancelInFlight: true)
	}

	private func resetDialog(_ state: inout State) {
		state.branchName = ""
		state.branchSearchText = ""
		state.availableBranches = []
		state.tickets = []
		state.ticketSearchError = nil
		state.isSearchingTickets = false
		state.selectedTicketId = nil
		state.pullRequests = []
		state.pullRequestFilter = ""
		state.pullRequestError = nil
		state.isLoadingPullRequests = false
		state.selectedPullRequestNumber = nil
		state.claudePrompt = ""
	}

	static func launch(for followUp: WorktreeCreationFollowUp, claudePrompt: String) -> WorktreeTerminalLaunch? {
		switch followUp {
		case .nothing: nil
		case .openTerminal: .terminal
		case .runClaude: .command(ClaudeCommand.make(prompt: claudePrompt))
		}
	}

	static func claudePrompt(for ticket: YouTrackIssueSummary, baseURL: String) -> String {
		let link = YouTrackURLBuilder.issueURL(baseURL: baseURL, ticketId: ticket.id).map { " (\($0))" } ?? ""
		return "Work on YouTrack ticket \(ticket.id): \(ticket.summary)\(link)"
	}

	static func claudePrompt(for pullRequest: OpenPullRequest) -> String {
		"Continue work on \(pullRequest.provider == .gitlab ? "MR" : "PR") \(pullRequest.reference): "
			+ "\(pullRequest.title) (\(pullRequest.url))"
	}

	static func ticketErrorMessage(for error: Error) -> String {
		switch error {
		case YouTrackServiceError.missingToken:
			"Add a YouTrack token in Settings to search tickets."
		case YouTrackServiceError.httpFailure(statusCode: 400):
			"YouTrack could not read that query."
		case YouTrackServiceError.httpFailure(statusCode: 401),
		     YouTrackServiceError.httpFailure(statusCode: 403):
			"YouTrack rejected the token — check it in Settings."
		case let YouTrackServiceError.httpFailure(statusCode):
			"YouTrack search failed: HTTP \(statusCode)"
		default:
			"YouTrack search failed: \(error.localizedDescription)"
		}
	}

	static func pullRequestErrorMessage(for error: Error, host: String) -> String {
		let provider = host.lowercased() == "gitlab.com" ? "GitLab" : "GitHub"
		switch error {
		case GitHostingError.missingToken:
			return "Add a \(provider) token in Settings to list open \(provider == "GitLab" ? "MRs" : "PRs")."
		case GitHostingError.httpFailure(statusCode: 401),
		     GitHostingError.unauthenticated:
			return "The \(provider) token can't access this repository — check it in Settings."
		case let GitHostingError.httpFailure(statusCode):
			return "\(provider) request failed: HTTP \(statusCode)"
		default:
			return "\(provider) request failed: \(error.localizedDescription)"
		}
	}
}
