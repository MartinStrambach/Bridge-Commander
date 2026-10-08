import ComposableArchitecture
import Foundation

/// The Continuations page's part of the Homer API. Errors are `HomerAPIError`s.
@DependencyClient
public struct HomerContinuationsClient: Sendable {
	/// The continuations in one status the user may see.
	public var continuations: @Sendable (_ baseURL: String, _ status: HomerContinuationStatus) async throws -> [HomerContinuation]
	/// Cancels a pending continuation: its agent never starts.
	public var cancel: @Sendable (_ baseURL: String, _ id: Int) async throws -> Void
	/// How many pending continuations the user may see, for the page's badge.
	public var pendingCount: @Sendable (_ baseURL: String) async throws -> Int
}

extension HomerContinuationsClient: DependencyKey {
	public static let liveValue = HomerContinuationsClient(
		continuations: { try await HomerAPI.continuations(baseURL: $0, status: $1) },
		cancel: { try await HomerAPI.cancelContinuation(baseURL: $0, id: $1) },
		pendingCount: { try await HomerAPI.pendingContinuationCount(baseURL: $0) }
	)
}

extension HomerContinuationsClient: TestDependencyKey {
	public static let testValue = HomerContinuationsClient()
}
