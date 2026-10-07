import ComposableArchitecture
import DependenciesTestSupport
import Foundation
@testable import HomerFeature
import Testing

@MainActor
@Suite("Homer sign-in form", .dependencies)
struct HomerSignInReducerTests {
	private static let baseURL = "https://homer.example.com"
	private let admin = HomerUser(username: "admin", role: "admin")

	private func filledForm() -> HomerSignInReducer.State {
		var state = HomerSignInReducer.State(baseURL: Self.baseURL)
		state.username = "admin"
		state.password = "nope"
		return state
	}

	@Test("a pasted page URL signs in to its instance, reported to the parent")
	func signInNormalizesURL() async {
		let loginArguments = LockIsolated<[String]>([])
		let store = TestStore(initialState: HomerSignInReducer.State(addingInstanceCanCancel: true)) {
			HomerSignInReducer()
		} withDependencies: {
			$0[HomerClient.self].login = { baseURL, username, password in
				loginArguments.setValue([baseURL, username, password])
				return admin
			}
		}

		await store.send(.binding(.set(\.endpoint, "https://homer.example.com/processes"))) {
			$0.endpoint = "https://homer.example.com/processes"
		}
		await store.send(.binding(.set(\.username, " admin "))) {
			$0.username = " admin "
		}
		await store.send(.binding(.set(\.password, "secret"))) {
			$0.password = "secret"
		}
		await store.send(.signInTapped) {
			$0.endpoint = Self.baseURL
			$0.isSigningIn = true
		}
		await store.receive(\.signInFinished) {
			$0.isSigningIn = false
			$0.password = ""
		}
		await store.receive(\.delegate.signedIn)

		#expect(loginArguments.value == [Self.baseURL, "admin", "secret"])
	}

	@Test("a URL that is not one says so before calling anything")
	func invalidEndpoint() async {
		var initialState = HomerSignInReducer.State(addingInstanceCanCancel: false)
		initialState.endpoint = "ftp://homer.example.com"
		let store = TestStore(initialState: initialState) {
			HomerSignInReducer()
		}

		await store.send(.signInTapped) {
			$0.loginError = HomerEndpointError.unsupportedScheme.localizedDescription
		}
	}

	@Test("a wrong password says so and keeps the form")
	func invalidCredentials() async {
		let store = TestStore(initialState: filledForm()) {
			HomerSignInReducer()
		} withDependencies: {
			$0[HomerClient.self].login = { _, _, _ in throw HomerAPIError.unauthorized }
		}

		await store.send(.signInTapped) {
			$0.isSigningIn = true
		}
		await store.receive(\.signInFinished) {
			$0.isSigningIn = false
			$0.loginError = "Invalid credentials. Please try again."
		}
	}

	@Test("the login limiter's 429 holds the button for a minute")
	func rateLimitedCooldown() async {
		let clock = TestClock()
		let store = TestStore(initialState: filledForm()) {
			HomerSignInReducer()
		} withDependencies: {
			$0.continuousClock = clock
			$0[HomerClient.self].login = { _, _, _ in throw HomerAPIError.rateLimited }
		}

		await store.send(.signInTapped) {
			$0.isSigningIn = true
		}
		await store.receive(\.signInFinished) {
			$0.isSigningIn = false
			$0.loginError = "Too many login attempts. Please wait a moment before trying again."
			$0.loginCooldown = 60
		}

		// Ignored while cooling down.
		await store.send(.signInTapped)

		await clock.advance(by: .seconds(1))
		await store.receive(\.loginCooldownTicked) {
			$0.loginCooldown = 59
		}
		await store.skipInFlightEffects()
	}

	@Test("the first instance's form has nothing to cancel back to")
	func cancelOnlyWithSomewhereToGo() async {
		let store = TestStore(initialState: HomerSignInReducer.State(addingInstanceCanCancel: false)) {
			HomerSignInReducer()
		}
		await store.send(.cancelTapped)

		let cancellable = TestStore(initialState: HomerSignInReducer.State(addingInstanceCanCancel: true)) {
			HomerSignInReducer()
		}
		await cancellable.send(.cancelTapped)
		await cancellable.receive(\.delegate.cancelled)
	}
}
