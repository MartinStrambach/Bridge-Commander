import Foundation
import Testing
@testable import ToolsIntegration

@Suite("YouTrack URL builder")
struct YouTrackURLBuilderTests {
	@Test func normalizedBaseKeepsCleanOrigin() {
		#expect(YouTrackURLBuilder.normalizedBase("https://youtrack.example.com") == "https://youtrack.example.com")
	}

	@Test func normalizedBaseTrimsWhitespace() {
		#expect(YouTrackURLBuilder.normalizedBase("  https://youtrack.example.com \n") == "https://youtrack.example.com")
	}

	@Test func normalizedBaseStripsTrailingSlashes() {
		#expect(YouTrackURLBuilder.normalizedBase("https://youtrack.example.com///") == "https://youtrack.example.com")
	}

	@Test func normalizedBaseStripsTrailingAPISegment() {
		#expect(YouTrackURLBuilder.normalizedBase("https://youtrack.example.com/api") == "https://youtrack.example.com")
		#expect(YouTrackURLBuilder.normalizedBase("https://youtrack.example.com/API/") == "https://youtrack.example.com")
	}

	@Test func normalizedBasePreservesInstancePath() {
		#expect(
			YouTrackURLBuilder.normalizedBase("https://org.myjetbrains.com/youtrack/")
				== "https://org.myjetbrains.com/youtrack"
		)
	}

	@Test func normalizedBaseEmptyInputsBecomeEmpty() {
		#expect(YouTrackURLBuilder.normalizedBase("") == "")
		#expect(YouTrackURLBuilder.normalizedBase("   ") == "")
		#expect(YouTrackURLBuilder.normalizedBase("/") == "")
	}

	@Test func issueURLIsNilWithoutBase() {
		#expect(YouTrackURLBuilder.issueURL(baseURL: "", ticketId: "MOB-1234") == nil)
		#expect(YouTrackURLBuilder.issueURL(baseURL: "  ", ticketId: "MOB-1234") == nil)
	}

	@Test func issueURLAppendsIssuePath() {
		#expect(
			YouTrackURLBuilder.issueURL(baseURL: "https://youtrack.example.com", ticketId: "MOB-1234")
				== "https://youtrack.example.com/issue/MOB-1234"
		)
	}

	@Test func issueURLToleratesTrailingSlash() {
		#expect(
			YouTrackURLBuilder.issueURL(baseURL: "https://youtrack.example.com/", ticketId: "MOB-1234")
				== "https://youtrack.example.com/issue/MOB-1234"
		)
	}

	@Test func serviceThrowsMissingBaseURLBeforeAnyNetworkIO() async {
		await #expect(throws: YouTrackServiceError.self) {
			try await YouTrackService.fetchIssueDetails(for: "MOB-1", baseURL: "", authToken: "token")
		}
		await #expect(throws: YouTrackServiceError.self) {
			try await YouTrackService.applyStateEvent(
				for: "MOB-1",
				fieldId: "84-950",
				eventId: "to review",
				baseURL: "/",
				authToken: "token"
			)
		}
	}
}
