import ComposableArchitecture
import DependenciesTestSupport
import Foundation
@testable import HomerFeature
import Testing

@MainActor
@Suite("Homer continuations page", .dependencies)
struct HomerContinuationsReducerTests {
	private static let baseURL = "https://homer.example.com"
	private let pending = HomerContinuation(
		id: 5,
		watchedProcessId: 12,
		status: .pending,
		agentName: "follow-up",
		originProcessId: 7,
		originAgentName: "starter",
		createdAt: 1_700_000_000
	)
	private let failed = HomerContinuation(
		id: 6,
		watchedProcessId: 13,
		status: .failed,
		agentName: "crash-report",
		originProcessId: 8,
		originAgentName: "factory",
		createdAt: 1_700_000_100,
		error: "boom"
	)

	private func shownState() -> HomerContinuationsReducer.State {
		var state = HomerContinuationsReducer.State(baseURL: Self.baseURL)
		state.isShown = true
		state.pending = [pending]
		state.failed = [failed]
		state.hasLoaded = true
		return state
	}

	@Test("shown loads the pending and failed lists, and polls every 30 s until hidden")
	func shownPollsUntilHidden() async {
		let clock = TestClock()
		let requests = LockIsolated<[HomerContinuationStatus]>([])
		let store = TestStore(initialState: HomerContinuationsReducer.State(baseURL: Self.baseURL)) {
			HomerContinuationsReducer()
		} withDependencies: { [pending, failed] in
			$0.continuousClock = clock
			$0[HomerContinuationsClient.self].continuations = { baseURL, status in
				#expect(baseURL == "https://homer.example.com")
				requests.withValue { $0.append(status) }
				return status == .pending ? [pending] : [failed]
			}
		}

		await store.send(.shown) {
			$0.isShown = true
		}
		await store.receive(\.loaded.success) {
			$0.pending = [pending]
			$0.failed = [failed]
			$0.hasLoaded = true
		}
		#expect(Set(requests.value) == [.pending, .failed])

		await clock.advance(by: HomerContinuationsReducer.pollInterval)
		await store.receive(\.loaded.success)
		#expect(requests.value.count == 4)

		await store.send(.hidden) {
			$0.isShown = false
		}
		await clock.advance(by: .seconds(120))
		#expect(requests.value.count == 4)
	}

	@Test("a failed refresh keeps the last lists under an error, and the next one clears it")
	func failedRefreshKeepsData() async {
		let clock = TestClock()
		let fails = LockIsolated(true)
		let store = TestStore(initialState: shownState()) {
			HomerContinuationsReducer()
		} withDependencies: { [pending, failed] in
			$0.continuousClock = clock
			$0[HomerContinuationsClient.self].continuations = { _, status in
				if fails.value {
					throw HomerAPIError.unreachable("offline")
				}
				return status == .pending ? [pending] : [failed]
			}
		}

		await store.send(.shown)
		await store.receive(\.loaded.failure) {
			$0.loadError = HomerAPIError.unreachable("offline").localizedDescription
		}

		fails.setValue(false)
		await clock.advance(by: HomerContinuationsReducer.pollInterval)
		await store.receive(\.loaded.success) {
			$0.loadError = nil
		}
		await store.send(.hidden) {
			$0.isShown = false
		}
	}

	@Test("a 401 asks the instance to sign out")
	func unauthorized() async {
		let store = TestStore(initialState: HomerContinuationsReducer.State(baseURL: Self.baseURL)) {
			HomerContinuationsReducer()
		} withDependencies: {
			$0.continuousClock = TestClock()
			$0[HomerContinuationsClient.self].continuations = { _, _ in throw HomerAPIError.unauthorized }
		}

		await store.send(.shown) {
			$0.isShown = true
		}
		await store.receive(\.loaded.failure)
		await store.receive(\.delegate, .unauthorized)
		// The instance answers with `hidden` (and replaces this state).
		await store.send(.hidden) {
			$0.isShown = false
		}
	}

	@Test("an answer landing after the page was hidden is dropped")
	func answerAfterHidden() async {
		let store = TestStore(initialState: HomerContinuationsReducer.State(baseURL: Self.baseURL)) {
			HomerContinuationsReducer()
		}

		await store.send(.loaded(.success(.init(pending: [pending], failed: []))))
		await store.send(.loaded(.failure(HomerAPIError.unauthorized)))
	}

	@Test("cancel asks first, then cancels by id and refetches")
	func cancelFlow() async {
		let clock = TestClock()
		let cancelled = LockIsolated<[Int]>([])
		let store = TestStore(initialState: shownState()) {
			HomerContinuationsReducer()
		} withDependencies: { [failed] in
			$0.continuousClock = clock
			$0[HomerContinuationsClient.self].cancel = { baseURL, id in
				#expect(baseURL == "https://homer.example.com")
				cancelled.withValue { $0.append(id) }
			}
			$0[HomerContinuationsClient.self].continuations = { _, status in
				status == .pending ? [] : [failed]
			}
		}

		await store.send(.cancelTapped(id: 5)) {
			$0.alert = AlertState {
				TextState("Cancel this continuation?")
			} actions: {
				ButtonState(role: .destructive, action: .cancelConfirmed(id: 5)) {
					TextState("Yes, Cancel")
				}
				ButtonState(role: .cancel) {
					TextState("Keep Waiting")
				}
			} message: {
				TextState("This stops follow-up from starting when run #12 finishes. This cannot be undone.")
			}
		}
		await store.send(.alert(.presented(.cancelConfirmed(id: 5)))) {
			$0.alert = nil
			$0.cancellingIDs = [5]
		}
		await store.receive(\.cancelFinished) {
			$0.cancellingIDs = []
			$0.pending = []
		}
		await store.receive(\.loaded.success)
		#expect(cancelled.value == [5])

		await store.send(.hidden) {
			$0.isShown = false
		}
	}

	@Test("a failed continuation offers no Cancel")
	func cancelOnlyPending() async {
		let store = TestStore(initialState: shownState()) {
			HomerContinuationsReducer()
		}

		await store.send(.cancelTapped(id: 6))
	}

	@Test("a cancel that comes too late says so on the card and refetches")
	func cancelConflict() async {
		let clock = TestClock()
		var initialState = shownState()
		initialState.cancellingIDs = [5]
		let store = TestStore(initialState: initialState) {
			HomerContinuationsReducer()
		} withDependencies: { [failed] in
			$0.continuousClock = clock
			$0[HomerContinuationsClient.self].continuations = { _, status in
				status == .pending ? [] : [failed]
			}
		}

		await store.send(.cancelFinished(id: 5, .failure(HomerAPIError.conflict))) {
			$0.cancellingIDs = []
			$0.cancelErrors = [5: HomerContinuationsReducer.notCancellableMessage]
		}
		// The continuation fired meanwhile: it and its error leave the page.
		await store.receive(\.loaded.success) {
			$0.pending = []
			$0.cancelErrors = [:]
		}
		await store.send(.hidden) {
			$0.isShown = false
		}
	}

	@Test("a cancel answering 401 asks the instance to sign out")
	func cancelUnauthorized() async {
		var initialState = shownState()
		initialState.cancellingIDs = [5]
		let store = TestStore(initialState: initialState) {
			HomerContinuationsReducer()
		}

		await store.send(.cancelFinished(id: 5, .failure(HomerAPIError.unauthorized))) {
			$0.cancellingIDs = []
		}
		await store.receive(\.delegate, .unauthorized)
	}

	@Test("a run number opens its web console page")
	func processTapped() async {
		let store = TestStore(initialState: shownState()) {
			HomerContinuationsReducer()
		}

		await store.send(.processTapped(processId: 12))
		await store.receive(\.delegate, .openWebConsole(path: "processes/12", title: "Process #12"))
	}
}
