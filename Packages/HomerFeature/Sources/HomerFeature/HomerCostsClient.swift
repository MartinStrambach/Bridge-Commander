import ComposableArchitecture
import Foundation

/// The Costs page's calls, addressed by the instance's base URL. Errors are `HomerAPIError`s.
@DependencyClient
public struct HomerCostsClient: Sendable {
	/// Rolling-window spend and the configured caps.
	public var snapshot: @Sendable (_ baseURL: String) async throws -> HomerCostSnapshot
	/// One UTC month (`YYYY-MM`) of the ledger; nil is the server's current month.
	public var monthly: @Sendable (_ baseURL: String, _ month: String?) async throws -> HomerMonthlyCosts
	/// All-time spend from the ledger.
	public var totals: @Sendable (_ baseURL: String) async throws -> HomerTotalCosts
}

extension HomerCostsClient: DependencyKey {
	public static let liveValue = HomerCostsClient(
		snapshot: { try await HomerAPI.costSnapshot(baseURL: $0) },
		monthly: { try await HomerAPI.monthlyCosts(baseURL: $0, month: $1) },
		totals: { try await HomerAPI.totalCosts(baseURL: $0) }
	)
}

extension HomerCostsClient: TestDependencyKey {
	public static let testValue = HomerCostsClient()
}
