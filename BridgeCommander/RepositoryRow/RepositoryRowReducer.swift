import ComposableArchitecture
import Foundation

// MARK: - Repository Row Reducer

@Reducer
struct RepositoryRowReducer {
	@ObservableState
	struct State: Equatable, Identifiable {
		var id: String
		var name: String
		var path: String
		var isWorktree: Bool

		var branchName: String?
		var ticketId: String?
		var unstagedChangesCount: Int
		var stagedChangesCount: Int

		var unpushedCommitCount: Int
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

		fileprivate var lastRefreshTime: Date?

		var formattedBranchName: String {
			BranchNameFormatter.format(branchName, ticketId: ticketId)
		}

		init(path: String, name: String, isWorktree: Bool = false) {
			self.id = path
			self.path = path
			self.name = name
			self.isWorktree = isWorktree

			self.branchName = name
			let ticketId = GitBranchDetector.extractTicketId(from: name)
			self.ticketId = ticketId
			self.unstagedChangesCount = 0
			self.stagedChangesCount = 0

			self.unpushedCommitCount = 0

			self.xcodeButton = .init(repositoryPath: path)
			self.tuistButton = .init(repositoryPath: path)
			self.terminalButton = .init(repositoryPath: path)
			self.claudeCodeButton = .init(repositoryPath: path)
			self.androidStudioButton = .init(repositoryPath: path)
			if let ticketId {
				self.ticketButton = .init(ticketId: ticketId)
			}
			self.shareButton = .init(
				branchName: name,
				ticketURL: ticketId != nil ? "https://youtrack.livesport.eu/issue/\(ticketId!)" : "",
			)
			self.deleteWorktreeButton = .init(name: name, path: path)
			self.createWorktreeButton = .init(repositoryPath: path)
			self.gitActionsMenu = .init(repositoryPath: path, currentBranch: name)
		}
	}

	enum Action {
		case onAppear
		case requestRefresh
		case didFetchBranch(String, Int, Int)
		case didFetchUnpushedCount(Int)
		case didFetchYouTrack(
			prUrl: String?,
			androidCR: CodeReviewState?,
			iosCR: CodeReviewState?,
			androidReviewerName: String?,
			iosReviewerName: String?,
			ticketState: TicketState?
		)
		case retryFetch(FetchType)
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

		enum FetchType: Equatable {
			case branch
			case unpushed
			case youTrack
		}
	}

	@Dependency(\.gitService)
	private var gitService

	@Dependency(\.youTrackService)
	private var youTrackService

	@Dependency(\.xcodeService)
	private var xcodeService

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
			case .onAppear,
			     .requestRefresh:
				state.lastRefreshTime = Date()
				return .merge(
					fetchBranch(for: &state),
					fetchUnpushed(for: &state),
					fetchYouTrack(for: &state),
					.send(.gitActionsMenu(.onAppear))
				)

			case let .didFetchBranch(branch, unstaged, staged):
				state.branchName = branch
				state.unstagedChangesCount = unstaged
				state.stagedChangesCount = staged
				state.gitActionsMenu.currentBranch = branch
				return .none

			case let .didFetchUnpushedCount(count):
				state.unpushedCommitCount = count
				return .none

			case let .didFetchYouTrack(prUrl, androidCR, iosCR, androidReviewerName, iosReviewerName, ticketState):
				state.prUrl = prUrl
				state.androidCR = androidCR
				state.iosCR = iosCR
				state.androidReviewerName = androidReviewerName
				state.iosReviewerName = iosReviewerName
				state.ticketState = ticketState
				state.shareButton.updatePRURL(prUrl)
				return .none

			case let .retryFetch(fetchType):
				switch fetchType {
				case .branch:
					return fetchBranch(for: &state)
				case .unpushed:
					return fetchUnpushed(for: &state)
				case .youTrack:
					return fetchYouTrack(for: &state)
				}

			case let .deleteWorktreeButton(action):
				// Handle successful worktree deletion by sending signal to parent
				if case .didRemoveSuccessfully = action {
					return .send(.worktreeDeleted)
				}
				return .none

			case let .createWorktreeButton(action):
				// Handle successful worktree creation by sending signal to parent
				if case .didCreateSuccessfully = action {
					return .send(.worktreeCreated)
				}
				return .none

			case let .gitActionsMenu(action):
				// Refresh repository state after merge or pull completes (success or error)
				// Failed merges may leave the repository in merge-in-progress state
				if case .mergeMasterButton(.mergeMasterCompleted) = action {
					return .send(.requestRefresh)
				}
				if case .pullButton(.pullCompleted) = action {
					return .send(.requestRefresh)
				}
				return .none

			default:
				return .none
			}
		}
		.ifLet(\.ticketButton, action: \.ticketButton) {
			TicketButtonReducer()
		}
	}

	// MARK: - Private Effect Builders

	private func fetchBranch(for state: inout State) -> Effect<Action> {
		.run { [path = state.path] send in
			do {
				let (branch, unstaged, staged) = await gitService.getCurrentBranch(at: path)
				await send(.didFetchBranch(branch, unstaged, staged))
			}
			catch {
				print(error.localizedDescription)
			}
		}
	}

	private func fetchUnpushed(for state: inout State) -> Effect<Action> {
		.run { [path = state.path] send in
			do {
				let count = try await gitService.countUnpushedCommits(at: path)
				await send(.didFetchUnpushedCount(count))
			}
			catch {
				print(error.localizedDescription)
			}
		}
	}

	private func fetchYouTrack(for state: inout State) -> Effect<Action> {
		guard let branchName = state.branchName else {
			return .none
		}

		return .run { [branch = branchName] send in
			do {
				guard let ticketId = await youTrackService.extractTicketId(from: branch) else {
					await send(.didFetchYouTrack(
						prUrl: nil,
						androidCR: nil,
						iosCR: nil,
						androidReviewerName: nil,
						iosReviewerName: nil,
						ticketState: nil
					))
					return
				}

				let details = try await youTrackService.fetchIssueDetails(for: ticketId)
				await send(.didFetchYouTrack(
					prUrl: details.prUrl,
					androidCR: details.androidCR,
					iosCR: details.iosCR,
					androidReviewerName: details.androidReviewerName,
					iosReviewerName: details.iosReviewerName,
					ticketState: details.ticketState
				))
			}
			catch {
				print(error.localizedDescription)
			}
		}
	}
}
