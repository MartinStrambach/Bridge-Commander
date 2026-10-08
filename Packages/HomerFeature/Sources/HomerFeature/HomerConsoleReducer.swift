import ComposableArchitecture
import Foundation
internal import OrderedCollections

/// The Homer console section: every instance the user signed in to, each a live
/// `HomerInstanceReducer` with its own session, and the one on screen. All of them check their
/// session at launch and poll their open questions; only the selected one polls its processes,
/// and only while the section is on screen. Switching is instant: the instance shows its last
/// data, and refreshes right away.
@Reducer
public struct HomerConsoleReducer: Sendable {
	/// Instances past the ninth are in the menu, without a ⌘-digit shortcut.
	public static let shortcutInstanceLimit = 9

	/// The console's pages, in its sidebar's order.
	public enum Tab: CaseIterable, Equatable, Sendable {
		case processes
		case questions
		case continuations
		case schedules
		case agents
		case costs

		/// The console shows these to admins only (`sidebar.tsx`).
		public var isAdminOnly: Bool {
			self == .schedules || self == .costs
		}

		/// The page's route in the web console, which is also its title there.
		var webConsolePath: String {
			switch self {
			case .processes: "processes"
			case .questions: "questions"
			case .continuations: "continuations"
			case .schedules: "schedules"
			case .agents: "agents"
			case .costs: "costs"
			}
		}

		public var title: String {
			switch self {
			case .processes: "Processes"
			case .questions: "Questions"
			case .continuations: "Continuations"
			case .schedules: "Schedules"
			case .agents: "Agents"
			case .costs: "Costs"
			}
		}
	}

	@ObservableState
	public struct State: Equatable {
		@Shared(.homerInstanceURLs)
		public internal(set) var instanceURLs: [String] = []
		@Shared(.homerSelectedInstance)
		public internal(set) var selectedInstanceID = ""
		public internal(set) var instances: IdentifiedArrayOf<HomerInstanceReducer.State> = []
		/// The "Add Instance" form, shown in place of the selected instance — and always while
		/// there is none.
		public internal(set) var addInstance: HomerSignInReducer.State?
		/// Shared by the instances, so a switch keeps the page.
		public var tab: Tab = .processes

		/// Whether the section is on screen.
		var isVisible = false
		var hasStarted = false

		public init() {}

		public var selectedInstance: HomerInstanceReducer.State? {
			instances[id: selectedInstanceID]
		}

		/// Every instance's open questions, for the section switcher's badge.
		public var openQuestionCount: Int {
			instances.reduce(0) { $0 + $1.openQuestionCount }
		}

		/// The instances other than the selected one have this many open questions between
		/// them — the instance menu shows it, as a reason to switch.
		public var otherInstancesOpenQuestionCount: Int {
			openQuestionCount - (selectedInstance?.openQuestionCount ?? 0)
		}
	}

	public enum Action: BindableAction {
		case binding(BindingAction<State>)
		/// Once per launch: every known instance checks its stored session.
		case start
		case appeared
		case disappeared

		case instanceSelected(HomerInstanceReducer.State.ID)
		case addInstanceTapped
		/// Signs the instance out and forgets it.
		case removeInstanceTapped(HomerInstanceReducer.State.ID)
		case refreshTapped
		/// A page of the selected instance's web console, e.g. `processes`.
		case openWebConsoleTapped(path: String, title: String)

		case addInstance(HomerSignInReducer.Action)
		case instances(IdentifiedActionOf<HomerInstanceReducer>)
	}

	@Dependency(HomerClient.self)
	private var homerClient

	public init() {}

	public var body: some Reducer<State, Action> {
		BindingReducer()
		Reduce { state, action in
			switch action {
			case .binding(\.tab):
				guard let id = state.selectedInstance?.id else {
					return .none
				}
				return send(.pageChanged(state.tab), to: id)

			case .binding:
				return .none

			case .start:
				guard !state.hasStarted else {
					return .none
				}
				state.hasStarted = true
				state.instances = IdentifiedArray(
					state.instanceURLs.map(HomerInstanceReducer.State.init(baseURL:)),
					uniquingIDsWith: { first, _ in first }
				)
				if state.selectedInstance == nil {
					state.$selectedInstanceID.withLock { [first = state.instances.first?.id] in $0 = first ?? "" }
				}
				if state.instances.isEmpty {
					state.addInstance = HomerSignInReducer.State(addingInstanceCanCancel: false)
				}
				return .merge(
					.merge(state.instances.ids.map { send(.start, to: $0) }),
					activateSelected(&state)
				)

			case .appeared:
				state.isVisible = true
				return activateSelected(&state)

			case .disappeared:
				state.isVisible = false
				return state.selectedInstance.map { send(.deactivated, to: $0.id) } ?? .none

			case let .instanceSelected(id):
				guard state.instances[id: id] != nil else {
					return .none
				}
				// Picking an instance is also the way out of the add form.
				state.addInstance = nil
				return select(id, &state)

			case .addInstanceTapped:
				state.addInstance = HomerSignInReducer.State(addingInstanceCanCancel: !state.instances.isEmpty)
				return .none

			case .addInstance(.delegate(.cancelled)):
				guard !state.instances.isEmpty else {
					return .none
				}
				state.addInstance = nil
				return .none

			case let .addInstance(.delegate(.signedIn(baseURL, user))):
				state.addInstance = nil
				if state.instances[id: baseURL] == nil {
					state.instances.append(HomerInstanceReducer.State(baseURL: baseURL))
					state.$instanceURLs.withLock { [ids = state.instances.ids.elements] in $0 = ids }
				}
				return .merge(select(baseURL, &state), send(.signedIn(user), to: baseURL))

			case .addInstance:
				return .none

			case let .removeInstanceTapped(id):
				guard state.instances.remove(id: id) != nil else {
					return .none
				}
				state.$instanceURLs.withLock { [ids = state.instances.ids.elements] in $0 = ids }
				@Shared(.homerUsernames) var usernames
				$usernames.withLock { _ = $0.removeValue(forKey: id) }
				if state.instances.isEmpty {
					state.addInstance = HomerSignInReducer.State(addingInstanceCanCancel: false)
				}
				// Removing the instance cancels its effects; the sign-out is the console's own,
				// so it outlives it.
				let signOut = Effect<Action>.run { _ in
					try? await homerClient.logout(id)
				}
				guard state.selectedInstanceID == id else {
					return signOut
				}
				state.$selectedInstanceID.withLock { [first = state.instances.first?.id] in $0 = first ?? "" }
				return .merge(signOut, activateSelected(&state))

			case .refreshTapped:
				return state.selectedInstance.map { send(.refreshTapped, to: $0.id) } ?? .none

			case let .openWebConsoleTapped(path, title):
				return state.selectedInstance.map { send(.openWebConsoleTapped(path: path, title: title), to: $0.id) }
					?? .none

			case .instances:
				return .none
			}
		}
		.ifLet(\.addInstance, action: \.addInstance) {
			HomerSignInReducer()
		}
		.forEach(\.instances, action: \.instances) {
			HomerInstanceReducer()
		}
	}

	/// Puts the instance on screen: the one it replaces stops polling its processes, and it
	/// starts — with a fetch right away, so its last data is current within a moment.
	private func select(_ id: HomerInstanceReducer.State.ID, _ state: inout State) -> Effect<Action> {
		let previousID = state.selectedInstanceID
		guard id != previousID else {
			return activateSelected(&state)
		}
		state.$selectedInstanceID.withLock { $0 = id }
		let tab = state.tab
		state.instances[id: id]?.page = tab
		guard state.isVisible else {
			return .none
		}
		return .merge(
			state.instances[id: previousID] == nil ? .none : send(.deactivated, to: previousID),
			send(.activated, to: id)
		)
	}

	/// The page is set directly rather than sent: `activated` reads it, so the instance comes on
	/// screen showing the console's page.
	private func activateSelected(_ state: inout State) -> Effect<Action> {
		guard state.isVisible, let id = state.selectedInstance?.id else {
			return .none
		}
		let tab = state.tab
		state.instances[id: id]?.page = tab
		return send(.activated, to: id)
	}

	private func send(_ action: HomerInstanceReducer.Action, to id: HomerInstanceReducer.State.ID) -> Effect<Action> {
		.send(.instances(.element(id: id, action: action)))
	}
}
