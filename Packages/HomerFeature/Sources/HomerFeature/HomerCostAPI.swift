import Foundation

/// The Costs page's calls (`getCosts`, `getMonthlyCosts`, `getTotalCosts` in
/// `console/lib/api/client.ts`). All three need the admin role; anyone else gets a 403.
extension HomerAPI {
	static func costSnapshot(baseURL: String) async throws -> HomerCostSnapshot {
		try await decode(HomerCostSnapshot.self, from: send("GET", "/api/v1/costs", baseURL: baseURL))
	}

	/// One UTC month (`YYYY-MM`); nil asks for the server's current month.
	static func monthlyCosts(baseURL: String, month: String?) async throws -> HomerMonthlyCosts {
		try await decode(
			HomerMonthlyCosts.self,
			from: send(
				"GET",
				"/api/v1/costs/monthly",
				baseURL: baseURL,
				queryItems: month.map { [URLQueryItem(name: "month", value: $0)] } ?? []
			)
		)
	}

	static func totalCosts(baseURL: String) async throws -> HomerTotalCosts {
		try await decode(HomerTotalCosts.self, from: send("GET", "/api/v1/costs/totals", baseURL: baseURL))
	}
}
