import ComposableArchitecture
import Foundation

/// The console's sign-in form (`app/(auth)/login/page.tsx`) in two roles: the form a signed-out
/// instance shows for its own URL, and "Add Instance", whose URL is the user's to type. A
/// successful sign-in is reported as `delegate(.signedIn)`; the session belongs to the parent.
@Reducer
public struct HomerSignInReducer: Sendable {
	/// How long the sign-in button stays off after the login limiter answers 429, as in the
	/// console: retrying sooner only drains the bucket and prolongs the lockout.
	static let loginCooldownSeconds = 60

	@ObservableState
	public struct State: Equatable {
		/// Adding an instance: the endpoint is a field. An instance's own form signs in to its URL
		/// only — another instance is added, not switched to from here.
		public let isAddingInstance: Bool
		/// Whether there is a console to go back to.
		public let canCancel: Bool
		public var endpoint: String
		public var username: String
		public var password = ""
		public internal(set) var loginError: String?
		public internal(set) var isSigningIn = false
		public internal(set) var loginCooldown = 0
		/// A session that was live ended (a call answered 401), as opposed to never having
		/// existed — the form says so, like the console's `?expired=1`.
		public internal(set) var sessionExpired = false

		/// The form of an instance already in the list.
		init(baseURL: String, username: String = "") {
			isAddingInstance = false
			canCancel = false
			endpoint = baseURL
			self.username = username
		}

		/// The form that adds an instance.
		init(addingInstanceCanCancel canCancel: Bool) {
			isAddingInstance = true
			self.canCancel = canCancel
			endpoint = ""
			username = ""
		}
	}

	public enum Action: BindableAction {
		case binding(BindingAction<State>)
		case signInTapped
		case signInFinished(baseURL: String, Result<HomerUser, any Error>)
		case loginCooldownTicked
		case cancelTapped
		case delegate(Delegate)

		@CasePathable
		public enum Delegate {
			case signedIn(baseURL: String, HomerUser)
			case cancelled
		}
	}

	private nonisolated enum CancelID: Hashable {
		case signIn
		case loginCooldown
	}

	@Dependency(HomerClient.self)
	private var homerClient

	@Dependency(\.continuousClock)
	private var clock

	public init() {}

	public var body: some Reducer<State, Action> {
		BindingReducer()
		Reduce { state, action in
			switch action {
			case .binding:
				return .none

			case .signInTapped:
				guard !state.isSigningIn, state.loginCooldown == 0 else {
					return .none
				}
				let baseURL: String
				do {
					baseURL = try HomerEndpoint.normalize(state.endpoint)
				}
				catch {
					state.loginError = error.localizedDescription
					return .none
				}
				let username = state.username.trimmingCharacters(in: .whitespacesAndNewlines)
				guard !username.isEmpty, !state.password.isEmpty else {
					state.loginError = "Enter your username and password."
					return .none
				}

				state.endpoint = baseURL
				state.loginError = nil
				state.isSigningIn = true
				return .run { [password = state.password] send in
					await send(.signInFinished(
						baseURL: baseURL,
						Result { try await homerClient.login(baseURL, username, password) }
					))
				}
				.cancellable(id: CancelID.signIn, cancelInFlight: true)

			case let .signInFinished(baseURL, .success(user)):
				state.isSigningIn = false
				state.password = ""
				state.sessionExpired = false
				return .send(.delegate(.signedIn(baseURL: baseURL, user)))

			case let .signInFinished(_, .failure(error)):
				state.isSigningIn = false
				switch error as? HomerAPIError {
				case .unauthorized:
					state.loginError = "Invalid credentials. Please try again."

				case .rateLimited:
					state.loginError = "Too many login attempts. Please wait a moment before trying again."
					state.loginCooldown = Self.loginCooldownSeconds
					return .run { send in
						for _ in 0 ..< Self.loginCooldownSeconds {
							try await clock.sleep(for: .seconds(1))
							await send(.loginCooldownTicked)
						}
					}
					.cancellable(id: CancelID.loginCooldown, cancelInFlight: true)

				default:
					state.loginError = error.localizedDescription
				}
				return .none

			case .loginCooldownTicked:
				state.loginCooldown = max(0, state.loginCooldown - 1)
				return .none

			case .cancelTapped:
				guard state.canCancel else {
					return .none
				}
				return .merge(.cancel(id: CancelID.signIn), .send(.delegate(.cancelled)))

			case .delegate:
				return .none
			}
		}
	}
}
