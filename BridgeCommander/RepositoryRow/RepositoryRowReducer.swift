import ComposableArchitecture
import Foundation

// MARK: - Repository Row Reducer

@Reducer
struct RepositoryRowReducer {
	@ObservableState
	struct State: Equatable, Identifiable {
		let id: String
		let path: String
		var ticketId: String?

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

		var isLoaded = false

		var supportsIOS: Bool
		var supportsAndroid: Bool
		var supportsTuist: Bool
		/// Empty when not (supportsIOS && supportsAndroid). Passed to Terminal, Claude Code, Android Studio.
		var mobileSubfolderPath: String
		/// Passed to Tuist and Xcode. Empty unless supportsIOS.
		var iosSubfolderPath: String
		/// Regex for extracting ticket IDs from branch names. Empty = no ticket parsing.
		var ticketIdRegex: String

		@Presents
		var repositoryDetail: RepositoryDetail.State?

		var formattedBranchName: String {
			@Shared(.branchNameRegex)
			var regex = "[a-zA-Z]+-\\d+[_/]"

			return BranchNameFormatter.format(branchName, ticketId: ticketId, branchNameRegex: regex)
		}

		init(
			path: String,
			name: String,
			branchName: String?,
			isWorktree: Bool = false,
			supportsIOS: Bool = false,
			supportsAndroid: Bool = false,
			mobileSubfolderPath: String = "",
			iosSubfolderPath: String = "",
			supportsTuist: Bool = false,
			ticketIdRegex: String = ""
		) {
			self.id = path
			self.path = path
			self.name = name
			self.isWorktree = isWorktree

			self.branchName = branchName

			let ticketId: String? =
				if ticketIdRegex.isEmpty {
					nil
				}
				else {
					GitBranchDetector.extractTicketId(from: branchName ?? name, pattern: ticketIdRegex)
				}
			self.ticketId = ticketId
			self.ticketIdRegex = ticketIdRegex
			self.unstagedChangesCount = 0
			self.stagedChangesCount = 0

			self.unpushedCommitCount = 0
			self.commitsBehindCount = 0
			self.hasRemoteBranch = true

			self.supportsIOS = supportsIOS
			self.supportsAndroid = supportsAndroid
			self.supportsTuist = supportsTuist
			self.mobileSubfolderPath = mobileSubfolderPath
			self.iosSubfolderPath = iosSubfolderPath

			self.xcodeButton = .init(repositoryPath: path, iosSubfolderPath: iosSubfolderPath)
			self.tuistButton = .init(repositoryPath: path, iosSubfolderPath: iosSubfolderPath)
			self.terminalButton = .init(repositoryPath: path, mobileSubfolderPath: mobileSubfolderPath)
			self.claudeCodeButton = .init(repositoryPath: path, mobileSubfolderPath: mobileSubfolderPath)
			self.androidStudioButton = .init(repositoryPath: path, mobileSubfolderPath: mobileSubfolderPath)
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
		case didFetchStatus(GitPorcelainStatus, Bool)
		case didFetchYouTrack(IssueDetails)
		case openRepositoryDetail
		case openTerminalForRepo
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

			case .onAppear:
				guard !state.isLoaded else {
					return .none
				}

				state.isLoaded = true
				return .merge(
					fetchBranchInfo(for: state),
					fetchYouTrack(for: state),
					.send(.gitActionsMenu(.onAppear)),
					.send(.xcodeButton(.onAppear))
				)

			case .refresh:
				return .merge(
					fetchBranchInfo(for: state),
					fetchYouTrack(for: state),
					.send(.gitActionsMenu(.refresh)),
					.send(.xcodeButton(.refresh))
				)

			case let .didFetchStatus(status, isMerge):
				let branch = status.branch ?? "unknown"
				let unstaged = isMerge ? 0 : status.unstagedCount
				let staged = isMerge ? 0 : status.stagedCount
				state.branchName = branch
				let newTicketId = state.ticketIdRegex.isEmpty
					? nil
					: GitBranchDetector.extractTicketId(from: branch, pattern: state.ticketIdRegex)
				state.ticketId = newTicketId
				state.ticketButton = newTicketId.map { TicketButtonReducer.State(ticketId: $0) }
				state.shareButton.updateTicketURL(newTicketId.map { "https://youtrack.livesport.eu/issue/\($0)" } ?? "")
				state.unstagedChangesCount = unstaged
				state.stagedChangesCount = staged
				state.gitActionsMenu.currentBranch = branch
				state.commitsBehindCount = status.behindCount
				state.hasRemoteBranch = status.hasRemoteBranch
				state.unpushedCommitCount = status.unpushedCount
				let hasChanges = unstaged > 0 || staged > 0
				state.gitActionsMenu.stashButton.hasChanges = hasChanges
				state.gitActionsMenu.unpushedCommitsCount = status.unpushedCount
				state.gitActionsMenu.hasRemoteBranch = status.hasRemoteBranch
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

	private func fetchBranchInfo(for state: State) -> EffectOf<RepositoryRowReducer> {
		.run { [path = state.path] send in
			let info = await gitClient.getCurrentBranch(at: path)
			let isMerge = GitMergeDetector.isGitOperationInProgress(at: path)
			await send(.didFetchStatus(info, isMerge))
		}
	}

	private func fetchYouTrack(for state: State) -> EffectOf<RepositoryRowReducer> {
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
