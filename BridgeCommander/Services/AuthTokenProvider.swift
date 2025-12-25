import ComposableArchitecture
import Foundation

// MARK: - Auth Token Provider

protocol AuthTokenProviderType: Sendable {
	func getYouTrackAuthToken() -> String
}

struct AuthTokenProvider: AuthTokenProviderType {
	func getYouTrackAuthToken() -> String {
		UserDefaults.standard.string(forKey: "youtrackAuthToken") ?? ""
	}
}

private struct AuthTokenProviderKey: DependencyKey {
	static let liveValue: AuthTokenProviderType = AuthTokenProvider()
}

extension DependencyValues {
	var authTokenProvider: AuthTokenProviderType {
		get { self[AuthTokenProviderKey.self] }
		set { self[AuthTokenProviderKey.self] = newValue }
	}
}
