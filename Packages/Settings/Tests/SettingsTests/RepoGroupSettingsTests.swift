import Foundation
import Testing
@testable import Settings

@Suite("RepoGroupSettings.defaultBranch")
struct RepoGroupSettingsTests {
	@Test("defaults to empty string")
	func defaultsToEmpty() {
		#expect(RepoGroupSettings().defaultBranch == "")
	}

	@Test("decodes JSON missing defaultBranch as empty (backward compatible)")
	func decodesMissingKeyAsEmpty() throws {
		let json = Data(#"{"supportsIOS":true,"ticketIdRegex":"MOB-[0-9]+"}"#.utf8)
		let decoded = try JSONDecoder().decode(RepoGroupSettings.self, from: json)
		#expect(decoded.defaultBranch == "")
		#expect(decoded.supportsIOS == true)
	}

	@Test("round-trips a configured defaultBranch")
	func roundTripsConfiguredValue() throws {
		var settings = RepoGroupSettings()
		settings.defaultBranch = "develop"
		let data = try JSONEncoder().encode(settings)
		let decoded = try JSONDecoder().decode(RepoGroupSettings.self, from: data)
		#expect(decoded.defaultBranch == "develop")
	}
}

@Suite("RepoGroupSettings.youtrackBaseURL")
struct RepoGroupSettingsYouTrackBaseURLTests {
	@Test("defaults to empty string (integration disabled)")
	func defaultsToEmpty() {
		#expect(RepoGroupSettings().youtrackBaseURL == "")
	}

	@Test("decodes JSON missing youtrackBaseURL as empty (backward compatible)")
	func decodesMissingKeyAsEmpty() throws {
		let json = Data(#"{"supportsIOS":true,"ticketIdRegex":"MOB-[0-9]+"}"#.utf8)
		let decoded = try JSONDecoder().decode(RepoGroupSettings.self, from: json)
		#expect(decoded.youtrackBaseURL == "")
		#expect(decoded.supportsIOS == true)
	}

	@Test("round-trips a configured youtrackBaseURL")
	func roundTripsConfiguredValue() throws {
		var settings = RepoGroupSettings()
		settings.youtrackBaseURL = "https://youtrack.example.com"
		let data = try JSONEncoder().encode(settings)
		let decoded = try JSONDecoder().decode(RepoGroupSettings.self, from: data)
		#expect(decoded.youtrackBaseURL == "https://youtrack.example.com")
	}
}
