import ComposableArchitecture
import Foundation

/// A run's artifacts (`artifact-picker-dialog.tsx`): every file in its artifacts directory,
/// each saved to Downloads on a click.
@Reducer
public struct HomerArtifactsReducer: Sendable {
	@ObservableState
	public struct State: Equatable {
		public let baseURL: String
		public let processId: Int
		public internal(set) var artifacts: [HomerArtifact] = []
		public internal(set) var isLoading = false
		public internal(set) var hasLoaded = false
		public internal(set) var loadError: String?
		public internal(set) var downloadingPaths: Set<String> = []
		/// Where each saved file went, for "Show in Finder".
		public internal(set) var savedFiles: [String: URL] = [:]
		public internal(set) var downloadErrors: [String: String] = [:]

		public init(baseURL: String, processId: Int) {
			self.baseURL = baseURL
			self.processId = processId
		}
	}

	public enum Action {
		case task
		case refreshTapped
		case loaded(Result<[HomerArtifact], any Error>)
		case downloadTapped(path: String)
		case downloadFinished(path: String, Result<URL, any Error>)
		case delegate(Delegate)

		public enum Delegate: Equatable, Sendable {
			case unauthorized
		}
	}

	private nonisolated enum CancelID: Hashable {
		case load
	}

	@Dependency(HomerProcessDetailClient.self)
	private var client

	public init() {}

	public var body: some Reducer<State, Action> {
		Reduce { state, action in
			switch action {
			case .task, .refreshTapped:
				state.isLoading = true
				return .run { [baseURL = state.baseURL, processId = state.processId] send in
					await send(.loaded(Result { try await client.artifacts(baseURL, processId) }))
				}
				.cancellable(id: CancelID.load, cancelInFlight: true)

			case let .loaded(.success(artifacts)):
				state.isLoading = false
				state.hasLoaded = true
				state.loadError = nil
				state.artifacts = artifacts
				return .none

			case let .loaded(.failure(error)):
				state.isLoading = false
				if error as? HomerAPIError == .unauthorized {
					return .send(.delegate(.unauthorized))
				}
				state.loadError = error.localizedDescription
				return .none

			case let .downloadTapped(path):
				guard state.downloadingPaths.insert(path).inserted else {
					return .none
				}
				state.downloadErrors[path] = nil
				return .run { [baseURL = state.baseURL, processId = state.processId] send in
					await send(.downloadFinished(path: path, Result {
						try await client.downloadArtifact(baseURL, processId, path)
					}))
				}

			case let .downloadFinished(path, .success(url)):
				state.downloadingPaths.remove(path)
				state.savedFiles[path] = url
				return .none

			case let .downloadFinished(path, .failure(error)):
				state.downloadingPaths.remove(path)
				if error as? HomerAPIError == .unauthorized {
					return .send(.delegate(.unauthorized))
				}
				state.downloadErrors[path] = error.localizedDescription
				return .none

			case .delegate:
				return .none
			}
		}
	}
}
