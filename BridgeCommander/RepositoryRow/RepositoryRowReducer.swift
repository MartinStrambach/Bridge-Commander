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
		var isMergeInProgress: Bool
		var unstagedChangesCount: Int
		var stagedChangesCount: Int

		var unpushedCommitCount: Int
		var prUrl: String?
		var androidCR: String?
		var iosCR: String?
		var androidReviewerName: String?
		var iosReviewerName: String?

		var xcodeButton: XcodeProjectButtonReducer.State
		var terminalButton: TerminalButtonReducer.State
		var claudeCodeButton: ClaudeCodeButtonReducer.State
		var androidStudioButton: AndroidStudioButtonReducer.State
		var ticketButton: TicketButtonReducer.State?
		var deleteWorktreeButton: DeleteWorktreeButtonReducer.State

		fileprivate var lastRefreshTime: Date?

		var formattedBranchName: String {
			BranchNameFormatter.format(branchName, ticketId: ticketId)
		}

		init(path: String, name: String, isWorktree: Bool = false) {
			self.id = path
			self.path = path
			self.name = name
			self.isWorktree = isWorktree

			self.branchName = nil
			self.ticketId = GitBranchDetector.extractTicketId(from: name)
			self.isMergeInProgress = false
			self.unstagedChangesCount = 0
			self.stagedChangesCount = 0

			self.unpushedCommitCount = 0
			self.prUrl = nil
			self.androidCR = nil
			self.iosCR = nil
			self.androidReviewerName = nil
			self.iosReviewerName = nil

			self.xcodeButton = .init(repositoryPath: path)
			self.terminalButton = .init(repositoryPath: path)
			self.claudeCodeButton = .init(repositoryPath: path)
			self.androidStudioButton = .init(repositoryPath: path)
			self.ticketButton = nil
			self.deleteWorktreeButton = .init(name: name, path: path)

			self.lastRefreshTime = nil
		}
	}

	enum Action {
		case onAppear
		case requestRefresh
		case didFetchBranch(String, Bool, Int, Int)
		case didFetchUnpushedCount(Int)
		case didFetchYouTrack(
			prUrl: String?,
			androidCR: String?,
			iosCR: String?,
			androidReviewerName: String?,
			iosReviewerName: String?
		)
		case retryFetch(FetchType)
		case xcodeButton(XcodeProjectButtonReducer.Action)
		case terminalButton(TerminalButtonReducer.Action)
		case claudeCodeButton(ClaudeCodeButtonReducer.Action)
		case androidStudioButton(AndroidStudioButtonReducer.Action)
		case ticketButton(TicketButtonReducer.Action)
		case deleteWorktreeButton(DeleteWorktreeButtonReducer.Action)
		case worktreeDeleted

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

		Scope(state: \.terminalButton, action: \.terminalButton) {
			TerminalButtonReducer()
		}

		Scope(state: \.claudeCodeButton, action: \.claudeCodeButton) {
			ClaudeCodeButtonReducer()
		}

		Scope(state: \.androidStudioButton, action: \.androidStudioButton) {
			AndroidStudioButtonReducer()
		}

		Scope(state: \.deleteWorktreeButton, action: \.deleteWorktreeButton) {
			DeleteWorktreeButtonReducer()
		}

		Reduce { state, action in
			switch action {
			case .onAppear:
				state.lastRefreshTime = Date()
				return .merge(
					fetchBranch(for: &state),
					fetchUnpushed(for: &state),
					fetchYouTrack(for: &state)
				)

			case .requestRefresh:
				state.lastRefreshTime = Date()
				return .merge(
					fetchBranch(for: &state),
					fetchUnpushed(for: &state),
					fetchYouTrack(for: &state)
				)

			case let .didFetchBranch(branch, isMerge, unstaged, staged):
				state.branchName = branch
				state.isMergeInProgress = isMerge
				state.unstagedChangesCount = unstaged
				state.stagedChangesCount = staged
				return .none

			case let .didFetchUnpushedCount(count):
				state.unpushedCommitCount = count
				return .none

			case let .didFetchYouTrack(prUrl, androidCR, iosCR, androidReviewerName, iosReviewerName):
				state.prUrl = prUrl
				state.androidCR = androidCR
				state.iosCR = iosCR
				state.androidReviewerName = androidReviewerName
				state.iosReviewerName = iosReviewerName
				if let ticketId = state.ticketId {
					state.ticketButton = .init(ticketId: ticketId)
				}
				else {
					state.ticketButton = nil
				}
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

			case .xcodeButton:
				return .none

			case .terminalButton:
				return .none

			case .claudeCodeButton:
				return .none

			case .androidStudioButton:
				return .none

			case .ticketButton:
				return .none

			case let .deleteWorktreeButton(action):
				// Handle successful worktree deletion by sending signal to parent
				if case .didRemoveSuccessfully = action {
					return .send(.worktreeDeleted)
				}
				return .none

			case .worktreeDeleted:
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
				let (branch, isMerge, unstaged, staged) = await gitService.getCurrentBranch(at: path)
				await send(.didFetchBranch(branch, isMerge, unstaged, staged))
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
						iosReviewerName: nil
					))
					return
				}

				let details = try await youTrackService.fetchIssueDetails(for: ticketId)
				await send(.didFetchYouTrack(
					prUrl: details.prUrl,
					androidCR: details.androidCR,
					iosCR: details.iosCR,
					androidReviewerName: details.androidReviewerName,
					iosReviewerName: details.iosReviewerName
				))
			}
			catch {
				print(error.localizedDescription)
			}
		}
	}
}
