import ComposableArchitecture
import Foundation

/// The Continuations page of one instance (`app/(dashboard)/continuations/page.tsx`): the
/// pending continuations — parked workflows waiting on a watched run to finish before starting
/// a follow-up agent — and the ones that failed to fire. A pending one can be cancelled.
@Reducer
public struct HomerContinuationsReducer: Sendable {
	/// The console's cadence (`useContinuations`): there is no continuation event to listen to.
	static let pollInterval: Duration = .seconds(30)

	/// What the console says when a cancel answers 409 or 404 — the list was stale.
	static let notCancellableMessage =
		"This continuation can no longer be cancelled — it already fired or was cancelled."

	@ObservableState
	public struct State: Equatable {
		public let baseURL: String
		public internal(set) var pending: IdentifiedArrayOf<HomerContinuation> = []
		/// Continuations that never started their follow-up agent. Agents use continuations to
		/// report crashes, so a lost one is a report nobody gets — the console lists them for
		/// that reason.
		public internal(set) var failed: IdentifiedArrayOf<HomerContinuation> = []
		public internal(set) var hasLoaded = false
		/// The last refresh's failure; the last good lists stay on screen under it.
		public internal(set) var loadError: String?
		/// Cancel requests still waiting on the server.
		public internal(set) var cancellingIDs: Set<HomerContinuation.ID> = []
		/// Why a cancel failed, shown on the continuation's card as the console does.
		public internal(set) var cancelErrors: [HomerContinuation.ID: String] = [:]
		@Presents
		public var alert: AlertState<Action.Alert>?
		/// Between `shown` and `hidden`. An answer arriving outside it is dropped.
		var isShown = false

		public init(baseURL: String) {
			self.baseURL = baseURL
		}
	}

	/// The two lists the page shows, fetched together.
	public struct Lists: Equatable, Sendable {
		public var pending: [HomerContinuation]
		public var failed: [HomerContinuation]

		public init(pending: [HomerContinuation], failed: [HomerContinuation]) {
			self.pending = pending
			self.failed = failed
		}
	}

	public enum Action {
		/// The page came on screen; it polls until `hidden`.
		case shown
		case hidden
		/// The header's Refresh: fetches right away, without waiting for the next poll.
		case refreshTapped
		case delegate(HomerPageDelegate)

		case loaded(Result<Lists, any Error>)
		case processTapped(processId: Int)
		case cancelTapped(id: HomerContinuation.ID)
		case cancelFinished(id: HomerContinuation.ID, Result<Void, any Error>)
		case alert(PresentationAction<Alert>)

		public enum Alert: Equatable, Sendable {
			case cancelConfirmed(id: HomerContinuation.ID)
		}
	}

	private nonisolated enum CancelID: Hashable {
		case polling
	}

	@Dependency(HomerContinuationsClient.self)
	private var client

	@Dependency(\.continuousClock)
	private var clock

	public init() {}

	public var body: some Reducer<State, Action> {
		Reduce { state, action in
			switch action {
			case .shown:
				state.isShown = true
				return poll(state)

			case .refreshTapped:
				return state.isShown ? poll(state) : .none

			case .hidden:
				state.isShown = false
				return .cancel(id: CancelID.polling)

			case .delegate:
				return .none

			case let .loaded(.success(lists)):
				guard state.isShown else {
					return .none
				}
				state.pending = IdentifiedArray(lists.pending, uniquingIDsWith: { first, _ in first })
				state.failed = IdentifiedArray(lists.failed, uniquingIDsWith: { first, _ in first })
				state.hasLoaded = true
				state.loadError = nil
				// A cancel error belongs to a card still offering Cancel.
				let pendingIDs = Set(state.pending.ids)
				state.cancelErrors = state.cancelErrors.filter { pendingIDs.contains($0.key) }
				return .none

			case let .loaded(.failure(error)):
				guard state.isShown else {
					return .none
				}
				if error as? HomerAPIError == .unauthorized {
					return .send(.delegate(.unauthorized))
				}
				state.loadError = error.localizedDescription
				return .none

			case let .processTapped(processId):
				return .send(.delegate(.openProcess(processId: processId)))

			case let .cancelTapped(id):
				guard let continuation = state.pending[id: id], continuation.isCancellable else {
					return .none
				}
				state.cancelErrors[id] = nil
				state.alert = AlertState {
					TextState("Cancel this continuation?")
				} actions: {
					ButtonState(role: .destructive, action: .cancelConfirmed(id: id)) {
						TextState("Yes, Cancel")
					}
					ButtonState(role: .cancel) {
						TextState("Keep Waiting")
					}
				} message: {
					TextState(
						"This stops \(continuation.agentName) from starting when run #\(continuation.watchedProcessId) finishes. This cannot be undone."
					)
				}
				return .none

			case let .alert(.presented(.cancelConfirmed(id))):
				guard state.cancellingIDs.insert(id).inserted else {
					return .none
				}
				return .run { [baseURL = state.baseURL] send in
					await send(.cancelFinished(id: id, Result { try await client.cancel(baseURL, id) }))
				}

			case .alert:
				return .none

			case let .cancelFinished(id, result):
				// Not waited on any more: the page's state was replaced (signed out) meanwhile.
				guard state.cancellingIDs.remove(id) != nil else {
					return .none
				}
				switch result {
				case .success:
					state.pending.remove(id: id)
				case let .failure(error):
					if error as? HomerAPIError == .unauthorized {
						return .send(.delegate(.unauthorized))
					}
					state.cancelErrors[id] = Self.cancelErrorMessage(error)
				}
				// Either way the lists are refetched, as the console does on settle: a 409/404
				// means what is shown was stale.
				return state.isShown ? poll(state) : .none
			}
		}
		.ifLet(\.$alert, action: \.alert)
	}

	static func cancelErrorMessage(_ error: any Error) -> String {
		switch error as? HomerAPIError {
		case .conflict, .server(status: 404, _):
			notCancellableMessage
		default:
			error.localizedDescription
		}
	}

	/// Fetches both lists right away, then on the console's cadence. Restarting it replaces the
	/// running loop, so an older answer never lands after a newer one.
	private func poll(_ state: State) -> Effect<Action> {
		.run { [baseURL = state.baseURL] send in
			while true {
				await send(.loaded(Result {
					async let pending = client.continuations(baseURL, .pending)
					async let failed = client.continuations(baseURL, .failed)
					return try await Lists(pending: pending, failed: failed)
				}))
				try await clock.sleep(for: Self.pollInterval)
			}
		}
		.cancellable(id: CancelID.polling, cancelInFlight: true)
	}
}
