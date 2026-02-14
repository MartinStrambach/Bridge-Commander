import ComposableArchitecture
import Foundation

// MARK: - Repository Row Reducer

@Reducer
struct RepositoryRowReducer {
	@ObservableState
	struct State: Equatable, Identifiable {
		let id: String
		let path: String
		let ticketId: String?

		var name: String
		var isWorktree: Bool
		var branchName: String?

		var unstagedChangesCount: Int
		var stagedChangesCount: Int

		var unpushedCommitCount: Int
		var commitsBehindCount: Int
		var hasRemoteBranch: Bool
		var prUrl: String?
		var androidCR: CodeReviewState?
		var iosCR: CodeReviewState?
		var androidReviewerName: String?
		var iosReviewerName: String?
		var ticketState: TicketState?

		var xcodeButton: XcodeProjectButtonReducer.State
		var tuistButton: TuistButtonReducer.State
		var terminalButton: TerminalButtonReducer.State
		var claudeCodeButton: ClaudeCodeButtonReducer.State
		var androidStudioButton: AndroidStudioButtonReducer.State
		var ticketButton: TicketButtonReducer.State?
		var shareButton: ShareButtonReducer.State
		var deleteWorktreeButton: DeleteWorktreeButtonReducer.State
		var createWorktreeButton: CreateWorktreeButtonReducer.State
		var gitActionsMenu: GitActionsMenuReducer.State

		@Presents
		var repositoryDetail: RepositoryDetail.State?

		var formattedBranchName: String {
			@Shared(.branchNameRegex)
			var regex = "[a-zA-Z]+-\\d+[_/]"

			return BranchNameFormatter.format(branchName, ticketId: ticketId, branchNameRegex: regex)
		}

		init(path: String, name: String, branchName: String?, isWorktree: Bool = false) {
			self.id = path
			self.path = path
			self.name = name
			self.isWorktree = isWorktree

			self.branchName = branchName

			// Access the shared ticketIdRegex setting
			@Shared(.ticketIdRegex)
			var regex = "MOB-[0-9]+"

			let ticketId = GitBranchDetector.extractTicketId(from: name, pattern: regex)
			self.ticketId = ticketId
			self.unstagedChangesCount = 0
			self.stagedChangesCount = 0

			self.unpushedCommitCount = 0
			self.commitsBehindCount = 0
			self.hasRemoteBranch = true

			self.xcodeButton = .init(repositoryPath: path)
			self.tuistButton = .init(repositoryPath: path)
			self.terminalButton = .init(repositoryPath: path)
			self.claudeCodeButton = .init(repositoryPath: path)
			self.androidStudioButton = .init(repositoryPath: path)
			if let ticketId {
				self.ticketButton = .init(ticketId: ticketId)
			}

			let ticketURL = ticketId.map { "https://youtrack.livesport.eu/issue/\($0)" } ?? ""
			self.shareButton = .init(
				branchName: branchName ?? name,
				ticketURL: ticketURL
			)
			self.deleteWorktreeButton = .init(name: branchName ?? name, path: path)
			self.createWorktreeButton = .init(repositoryPath: path)
			self.gitActionsMenu = .init(repositoryPath: path, currentBranch: name)
		}
	}

	enum Action {
		case onAppear
		case refresh
		case didFetchBranch(String, Int, Int)
		case didFetchUnpushedCount(Int)
		case didFetchCommitsBehind(Int)
		case didFetchRemoteBranch(Bool)
		case didFetchYouTrack(IssueDetails)
		case openRepositoryDetail
		case repositoryDetail(PresentationAction<RepositoryDetail.Action>)
		case xcodeButton(XcodeProjectButtonReducer.Action)
		case tuistButton(TuistButtonReducer.Action)
		case terminalButton(TerminalButtonReducer.Action)
		case claudeCodeButton(ClaudeCodeButtonReducer.Action)
		case androidStudioButton(AndroidStudioButtonReducer.Action)
		case ticketButton(TicketButtonReducer.Action)
		case shareButton(ShareButtonReducer.Action)
		case deleteWorktreeButton(DeleteWorktreeButtonReducer.Action)
		case createWorktreeButton(CreateWorktreeButtonReducer.Action)
		case gitActionsMenu(GitActionsMenuReducer.Action)
		case worktreeDeleted
		case worktreeCreated
	}

	@Dependency(GitClient.self)
	private var gitClient

	@Dependency(YouTrackClient.self)
	private var youTrackClient

	@Dependency(XcodeClient.self)
	private var xcodeClient

	var body: some Reducer<State, Action> {
		Scope(state: \.xcodeButton, action: \.xcodeButton) {
			XcodeProjectButtonReducer()
		}

		Scope(state: \.tuistButton, action: \.tuistButton) {
			TuistButtonReducer()
		}

		Scope(state: \.terminalButton, action: \.terminalButton) {
			TerminalButtonReducer()
		}

		Scope(state: \.claudeCodeButton, action: \.claudeCodeButton) {
			ClaudeCodeButtonReducer()
		}

		Scope(state: \.androidStudioButton, action: \.androidStudioButton) {
			AndroidStudioButtonReducer()
		}

		Scope(state: \.shareButton, action: \.shareButton) {
			ShareButtonReducer()
		}

		Scope(state: \.deleteWorktreeButton, action: \.deleteWorktreeButton) {
			DeleteWorktreeButtonReducer()
		}

		Scope(state: \.createWorktreeButton, action: \.createWorktreeButton) {
			CreateWorktreeButtonReducer()
		}

		Scope(state: \.gitActionsMenu, action: \.gitActionsMenu) {
			GitActionsMenuReducer()
		}

		Reduce { state, action in
			switch action {
			case .openRepositoryDetail:
				state.repositoryDetail = RepositoryDetail.State(repositoryPath: state.path)
				return .none

			case .onAppear,
			     .refresh:
				return .merge(
					fetchBranch(for: state),
					fetchUnpushed(for: state),
					fetchCommitsBehind(for: state),
					fetchRemoteBranch(for: state),
					fetchYouTrack(for: state),
					.send(.gitActionsMenu(.onAppear)),
					.send(.xcodeButton(.onAppear))
				)

			case let .didFetchBranch(branch, unstaged, staged):
				state.branchName = branch
				state.unstagedChangesCount = unstaged
				state.stagedChangesCount = staged
				state.gitActionsMenu.currentBranch = branch
				let hasChanges = unstaged > 0 || staged > 0
				return .send(.gitActionsMenu(.stashButton(.updateHasChanges(hasChanges))))

			case let .didFetchUnpushedCount(count):
				state.unpushedCommitCount = count
				return .none

			case let .didFetchCommitsBehind(count):
				state.commitsBehindCount = count
				return .none

			case let .didFetchRemoteBranch(hasRemote):
				state.hasRemoteBranch = hasRemote
				return .none

			case let .didFetchYouTrack(details):
				state.prUrl = details.prUrl
				state.androidCR = details.androidCR
				state.iosCR = details.iosCR
				state.androidReviewerName = details.androidReviewerName
				state.iosReviewerName = details.iosReviewerName
				state.ticketState = details.ticketState
				state.shareButton.updatePRURL(details.prUrl)
				return .none

			case let .deleteWorktreeButton(action):
				if case .didRemoveSuccessfully = action {
					return .send(.worktreeDeleted)
				}
				return .none

			case let .createWorktreeButton(action):
				if case .didCreateSuccessfully = action {
					return .send(.worktreeCreated)
				}
				return .none

			case let .gitActionsMenu(action):
				switch action {
				case .abortMergeButton(.abortMergeCompleted),
				     .fetchButton(.fetchCompleted),
				     .mergeMasterButton(.mergeMasterCompleted),
				     .pullButton(.pullCompleted),
				     .pushButton(.pushCompleted),
				     .stashButton(.stashCompleted),
				     .stashButton(.stashPopCompleted):
					return .send(.refresh)

				default:
					return .none
				}

			case .repositoryDetail(.dismiss):
				// Refresh when detail view is closed to pick up any staging changes
				return .send(.refresh)

			case .repositoryDetail:
				return .none

			default:
				return .none
			}
		}
		.ifLet(\.ticketButton, action: \.ticketButton) {
			TicketButtonReducer()
		}
		.ifLet(\.$repositoryDetail, action: \.repositoryDetail) {
			RepositoryDetail()
		}
	}

	// MARK: - Private Effect Builders

	private func fetchBranch(for state: State) -> Effect<Action> {
		.run { [path = state.path] send in
			let (branch, unstaged, staged) = await gitClient.getCurrentBranch(at: path)
			await send(.didFetchBranch(branch, unstaged, staged))
		}
	}

	private func fetchUnpushed(for state: State) -> Effect<Action> {
		.run { [path = state.path] send in
			let count = await gitClient.countUnpushedCommits(at: path)
			await send(.didFetchUnpushedCount(count))
		}
	}

	private func fetchCommitsBehind(for state: State) -> Effect<Action> {
		.run { [path = state.path] send in
			let count = await gitClient.countCommitsBehind(at: path)
			await send(.didFetchCommitsBehind(count))
		}
	}

	private func fetchRemoteBranch(for state: State) -> Effect<Action> {
		.run { [path = state.path] send in
			let hasRemote = await GitRemoteBranchDetector.hasRemoteBranch(at: path)
			await send(.didFetchRemoteBranch(hasRemote))
		}
	}

	private func fetchYouTrack(for state: State) -> Effect<Action> {
		guard let ticketId = state.ticketId else {
			return .none
		}

		return .run { send in
			do {
				let details = try await youTrackClient.fetchIssueDetails(for: ticketId)
				await send(.didFetchYouTrack(details))
			}
			catch {
				// Silently fail - YouTrack might be unavailable
				print("Failed to fetch YouTrack details for \(ticketId): \(error.localizedDescription)")
			}
		}
	}
}
