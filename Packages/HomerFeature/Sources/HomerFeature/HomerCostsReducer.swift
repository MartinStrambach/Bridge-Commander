import ComposableArchitecture
import Foundation

/// The Costs page of one instance (admins only), the console's `app/(dashboard)/costs/page.tsx`:
/// rolling-window spend against the configured caps, polled on the console's 5 s; and the
/// persistent ledger's month (with its month picker) and all-time totals, re-read every 30 s,
/// the console's `staleTime` for them.
@Reducer
public struct HomerCostsReducer: Sendable {
	/// `useCosts`' `refetchInterval`.
	static let snapshotPollInterval: Duration = .seconds(5)
	/// `useMonthlyCosts`/`useTotalCosts`' `staleTime`. The console re-reads stale ledger data
	/// when the page mounts or the window regains focus; a page left open here refreshes on it.
	static let ledgerPollInterval: Duration = .seconds(30)

	@ObservableState
	public struct State: Equatable {
		public let baseURL: String

		public internal(set) var snapshot: HomerCostSnapshot?
		public internal(set) var snapshotError: String?

		/// The month the picker chose, `YYYY-MM`; nil follows the server's current UTC month,
		/// into the next one when it turns.
		public internal(set) var selectedMonth: String?
		/// The last month read. While another month loads it stays on screen, dimmed, as the
		/// console keeps its previous data.
		public internal(set) var monthly: HomerMonthlyCosts?
		public internal(set) var monthlyError: String?

		public internal(set) var totals: HomerTotalCosts?
		public internal(set) var totalsError: String?

		/// Between `shown` and `hidden`: the page polls.
		var isShown = false

		public init(baseURL: String) {
			self.baseURL = baseURL
		}

		/// Whether `monthly` is the month the picker shows.
		public var isMonthlyCurrent: Bool {
			guard let monthly else {
				return false
			}
			return selectedMonth == nil || monthly.month == selectedMonth
		}

		/// The picker's choice: the month asked for, else the one the server answered with.
		public var shownMonth: String? {
			selectedMonth ?? monthly?.month
		}

		/// The picker's months, newest first.
		public var monthChoices: [String] {
			var months = Set(monthly?.pickerMonths ?? [])
			if let selectedMonth {
				months.insert(selectedMonth)
			}
			return months.sorted(by: >)
		}

		/// Nothing has answered yet, successfully or not.
		public var isLoading: Bool {
			snapshot == nil && monthly == nil && totals == nil
				&& snapshotError == nil && monthlyError == nil && totalsError == nil
		}

		/// The failed refreshes' messages, each once: an unreachable server fails all three calls
		/// with the same one.
		public var errorMessages: [String] {
			var seen = Set<String>()
			return [snapshotError, monthlyError, totalsError].compactMap(\.self).filter { seen.insert($0).inserted }
		}
	}

	public enum Action {
		/// The page came on screen; it polls until `hidden`.
		case shown
		case hidden
		/// The header's Refresh: fetches right away, without waiting for the next poll.
		case refreshTapped
		case monthSelected(String)
		case snapshotLoaded(Result<HomerCostSnapshot, any Error>)
		/// `month` is the one asked for (nil: the current one).
		case monthlyLoaded(month: String?, Result<HomerMonthlyCosts, any Error>)
		case totalsLoaded(Result<HomerTotalCosts, any Error>)
		case delegate(HomerPageDelegate)
	}

	private nonisolated enum CancelID: Hashable {
		case snapshotPolling
		case monthlyPolling
		case totalsPolling
	}

	@Dependency(HomerCostsClient.self)
	private var costsClient

	@Dependency(\.continuousClock)
	private var clock

	public init() {}

	public var body: some Reducer<State, Action> {
		Reduce { state, action in
			switch action {
			case .shown:
				guard !state.isShown else {
					return .none
				}
				state.isShown = true
				return .merge(pollSnapshot(state), pollMonthly(state), pollTotals(state))

			case .refreshTapped:
				return state.isShown ? .merge(pollSnapshot(state), pollMonthly(state), pollTotals(state)) : .none

			case .hidden:
				state.isShown = false
				return stopPolling()

			case let .monthSelected(month):
				guard month != state.shownMonth else {
					return .none
				}
				state.selectedMonth = month
				state.monthlyError = nil
				// Replaces the running loop, so the previous month's answer never lands after
				// this one's.
				return state.isShown ? pollMonthly(state) : .none

			case let .snapshotLoaded(.success(snapshot)):
				state.snapshot = snapshot
				state.snapshotError = nil
				return .none

			case let .snapshotLoaded(.failure(error)):
				return failed(error, at: \.snapshotError, &state)

			case let .monthlyLoaded(month, result):
				// Belt and braces: a month's loop is replaced when another is picked, so its
				// answer is dropped before it gets here anyway.
				guard month == state.selectedMonth else {
					return .none
				}
				switch result {
				case let .success(monthly):
					state.monthly = monthly
					state.monthlyError = nil
					return .none
				case let .failure(error):
					return failed(error, at: \.monthlyError, &state)
				}

			case let .totalsLoaded(.success(totals)):
				state.totals = totals
				state.totalsError = nil
				return .none

			case let .totalsLoaded(.failure(error)):
				return failed(error, at: \.totalsError, &state)

			case .delegate:
				return .none
			}
		}
	}

	/// A 401 is the instance's session ending: it signs out and replaces this state. Anything
	/// else is said above the last good data, which stays.
	private func failed(
		_ error: any Error,
		at message: WritableKeyPath<State, String?>,
		_ state: inout State
	) -> Effect<Action> {
		if error as? HomerAPIError == .unauthorized {
			state.isShown = false
			return .merge(stopPolling(), .send(.delegate(.unauthorized)))
		}
		state[keyPath: message] = error.localizedDescription
		return .none
	}

	private func stopPolling() -> Effect<Action> {
		.merge(
			.cancel(id: CancelID.snapshotPolling),
			.cancel(id: CancelID.monthlyPolling),
			.cancel(id: CancelID.totalsPolling)
		)
	}

	private func pollSnapshot(_ state: State) -> Effect<Action> {
		.run { [baseURL = state.baseURL] send in
			while true {
				await send(.snapshotLoaded(Result { try await costsClient.snapshot(baseURL) }))
				try await clock.sleep(for: Self.snapshotPollInterval)
			}
		}
		.cancellable(id: CancelID.snapshotPolling, cancelInFlight: true)
	}

	private func pollMonthly(_ state: State) -> Effect<Action> {
		.run { [baseURL = state.baseURL, month = state.selectedMonth] send in
			while true {
				await send(.monthlyLoaded(month: month, Result { try await costsClient.monthly(baseURL, month) }))
				try await clock.sleep(for: Self.ledgerPollInterval)
			}
		}
		.cancellable(id: CancelID.monthlyPolling, cancelInFlight: true)
	}

	private func pollTotals(_ state: State) -> Effect<Action> {
		.run { [baseURL = state.baseURL] send in
			while true {
				await send(.totalsLoaded(Result { try await costsClient.totals(baseURL) }))
				try await clock.sleep(for: Self.ledgerPollInterval)
			}
		}
		.cancellable(id: CancelID.totalsPolling, cancelInFlight: true)
	}
}
