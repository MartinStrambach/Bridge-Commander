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

@Suite("RepoGroupSettings.defaultWorktreeSource")
struct RepoGroupSettingsWorktreeSourceTests {
	@Test("round-trips a picked tab")
	func roundTrips() throws {
		let settings = RepoGroupSettings(defaultWorktreeSource: .pullRequest)
		let data = try JSONEncoder().encode(settings)
		let decoded = try JSONDecoder().decode(RepoGroupSettings.self, from: data)
		#expect(decoded.defaultWorktreeSource == .pullRequest)
	}

	@Test("an unknown tab reads as not picked and keeps the rest of the settings")
	func unknownTabIsNil() throws {
		let json = Data(#"{"supportsIOS":true,"defaultWorktreeSource":"someday"}"#.utf8)
		let decoded = try JSONDecoder().decode(RepoGroupSettings.self, from: json)
		#expect(decoded.defaultWorktreeSource == nil)
		#expect(decoded.supportsIOS == true)
	}

	@Test("Ticket is offered only with a YouTrack instance")
	func ticketNeedsYouTrack() {
		#expect(RepoGroupSettings().worktreeSources == [.branch, .pullRequest])
		#expect(RepoGroupSettings(youtrackBaseURL: "https://yt.example").worktreeSources == WorktreeSource.allCases)
	}

	@Test("the group's own pick wins over the app-wide fallback")
	func groupPickWins() {
		let settings = RepoGroupSettings(defaultWorktreeSource: .pullRequest)
		#expect(settings.openingWorktreeSource(fallback: .branch) == .pullRequest)
		#expect(RepoGroupSettings().openingWorktreeSource(fallback: .pullRequest) == .pullRequest)
	}

	@Test("a Ticket pick opens on Branch without a YouTrack instance")
	func ticketFallsBackToBranch() {
		#expect(RepoGroupSettings(defaultWorktreeSource: .ticket).openingWorktreeSource(fallback: .branch) == .branch)
		#expect(RepoGroupSettings().openingWorktreeSource(fallback: .ticket) == .branch)
		let withYouTrack = RepoGroupSettings(youtrackBaseURL: "https://yt.example", defaultWorktreeSource: .ticket)
		#expect(withYouTrack.openingWorktreeSource(fallback: .branch) == .ticket)
	}
}
