import ComposableArchitecture
import Foundation
import GitCore

@Reducer
public struct GitGraphReducer {
	@ObservableState
	public struct State: Equatable {
		public let repositoryPath: String
		let repositoryName: String
		var rows: [GitGraphRow] = []
		var isLoading = false
		var errorMessage: String?
		var commitLimit = GitGraphReducer.pageSize

		/// True when the last load filled the limit, so older commits likely exist
		var canLoadMore = false

		/// The commit whose diff is open in the bottom pane, or nil when none is selected.
		///
		/// Held separately from `commitDetail` so a row only has to observe this one property:
		/// reading the hash off the child state instead would re-render every visible row each
		/// time the child loaded a file list or a diff.
		var selectedCommitHash: String?

		var commitDetail: CommitDetailReducer.State?

		/// What the search field searches; kept when the query is cleared.
		var searchField: GitLogSearch.Field = .message

		/// The search field's text, as typed.
		var searchQuery = ""

		/// The search the graph is narrowed to, or nil for the whole history.
		var search: GitLogSearch? {
			GitLogSearch(field: searchField, query: searchQuery)
		}

		/// Where "New Worktree from Commit…" puts the worktree (relative to the main repository,
		/// like the row's Create Worktree button) and which untracked files it copies into it.
		/// Handed in by the presenter, which owns the settings.
		let worktreeBasePath: String
		let worktreeCopyPaths: [String]

		/// The working tree of the repository this one belongs to (itself, unless it is a linked
		/// worktree). Only used to show where a new worktree will go.
		let mainRepositoryPath: String

		/// The write action running now, as the header names it ("Cherry-picking…"). While it is
		/// set the commit menu offers nothing else, so two git commands never race each other.
		var runningCommitAction: String?

		/// The name prompt for "New Branch…" / "New Worktree…", or nil when it is closed.
		var branchForm: BranchForm?

		@Presents
		var alert: AlertState<CommitAction.Alert>?

		public init(
			repositoryPath: String,
			repositoryName: String,
			worktreeBasePath: String = "../worktrees",
			worktreeCopyPaths: [String] = []
		) {
			self.repositoryPath = repositoryPath
			self.repositoryName = repositoryName
			self.worktreeBasePath = worktreeBasePath
			self.worktreeCopyPaths = worktreeCopyPaths
			self.mainRepositoryPath = GitDirectoryResolver.resolveMainRepositoryPath(at: repositoryPath) ?? repositoryPath
		}
	}

	public enum Action {
		case task
		case refreshButtonTapped
		case loadMoreButtonTapped
		case closeButtonTapped
		case commitsLoaded([GitLogCommit])
		case loadFailed(String)
		case commitTapped(String)
		case closeDetailButtonTapped
		case commitDetail(CommitDetailReducer.Action)
		case searchQueryChanged(String)
		case searchFieldChanged(GitLogSearch.Field)
		case commitAction(CommitAction)
		case alert(PresentationAction<CommitAction.Alert>)
		case delegate(Delegate)

		@CasePathable
		public enum Delegate: Equatable {
			/// HEAD, the current branch or the working tree changed: the presenter's row is stale.
			case repositoryChanged
			/// A worktree was added at `path`, so the presenter's repository group needs a rescan.
			case worktreeCreated(path: String)
		}
	}

	static let pageSize = 300

	/// How long typing has to pause before the search runs. Each run is a full history walk
	/// (`-S` diffs every commit), so one per keystroke would mostly be cancelled work.
	static let searchDebounce: Duration = .milliseconds(300)

	private nonisolated enum CancellableId: Hashable {
		case loadCommits
	}

	@Dependency(\.dismiss)
	private var dismiss

	@Dependency(GitLogClient.self)
	private var gitLog

	@Dependency(GitCommitActionClient.self)
	var gitCommitActions

	@Dependency(\.continuousClock)
	private var clock

	public init() {}

	public var body: some Reducer<State, Action> {
		Reduce { state, action in
			switch action {
			case .task, .refreshButtonTapped:
				return loadCommits(state: &state)

			case .loadMoreButtonTapped:
				state.commitLimit += Self.pageSize
				return loadCommits(state: &state)

			case .closeButtonTapped:
				return .run { [dismiss] _ in await dismiss() }

			case let .commitsLoaded(commits):
				state.isLoading = false
				state.errorMessage = nil
				state.canLoadMore = commits.count >= state.commitLimit
				state.rows = GitGraphLayout.layout(commits: commits)

				// A reload can drop the selected commit (a rewritten branch, a narrower limit).
				// A commit that is still listed keeps its open diff: its content cannot change.
				if let selected = state.selectedCommitHash, !commits.contains(where: { $0.hash == selected }) {
					state.selectedCommitHash = nil
					state.commitDetail = nil
				}
				return .none

			case let .loadFailed(message):
				state.isLoading = false
				state.errorMessage = message
				return .none

			case let .commitTapped(hash):
				guard
					state.selectedCommitHash != hash,
					let commit = state.rows.first(where: { $0.commit.hash == hash })?.commit
				else {
					return .none
				}

				state.selectedCommitHash = hash
				state.commitDetail = CommitDetailReducer.State(
					repositoryPath: state.repositoryPath,
					commit: commit
				)
				// Driven from here rather than the view's `.task`, so re-selecting always loads
				// even when SwiftUI reuses the pane for the new commit.
				return .send(.commitDetail(.task))

			case .closeDetailButtonTapped:
				state.selectedCommitHash = nil
				state.commitDetail = nil
				return .none

			case .commitDetail:
				return .none

			case let .searchQueryChanged(query):
				let previous = state.search
				state.searchQuery = query
				return searchChanged(from: previous, state: &state)

			case let .searchFieldChanged(field):
				let previous = state.search
				state.searchField = field
				return searchChanged(from: previous, state: &state)

			case let .commitAction(action):
				return reduce(commitAction: action, state: &state)

			case let .alert(.presented(action)):
				return reduce(alertAction: action, state: &state)

			case .alert, .delegate:
				return .none
			}
		}
		.ifLet(\.commitDetail, action: \.commitDetail) {
			CommitDetailReducer()
		}
		.ifLet(\.$alert, action: \.alert)
	}

	/// Reloads for a changed search. Edits that leave the search as it was (whitespace around the
	/// query, a different field while the query is empty) load nothing.
	private func searchChanged(from previous: GitLogSearch?, state: inout State) -> Effect<Action> {
		guard state.search != previous else {
			return .none
		}

		// Load More raised the limit for the previous results; a new search starts at one page.
		state.commitLimit = Self.pageSize
		// Clearing the search brings the whole graph back at once; only a query waits for typing to pause.
		return loadCommits(state: &state, debounce: state.search != nil)
	}

	func loadCommits(state: inout State, debounce: Bool = false) -> Effect<Action> {
		state.isLoading = true
		return .run { [clock, gitLog, path = state.repositoryPath, limit = state.commitLimit, search = state.search] send in
			if debounce {
				try await clock.sleep(for: Self.searchDebounce)
			}

			do {
				let commits = try await gitLog.loadCommits(path, limit, search)
				await send(.commitsLoaded(commits))
			}
			catch {
				await send(.loadFailed(error.localizedDescription))
			}
		}
		.cancellable(id: CancellableId.loadCommits, cancelInFlight: true)
	}
}
