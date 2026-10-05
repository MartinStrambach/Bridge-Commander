import Foundation
import Testing
@testable import ToolsIntegration

@Suite("Ticket → branch name")
struct TicketBranchNameTests {
	private let template = BranchNameFormatter.defaultTicketBranchTemplate

	@Test("the default puts the summary's words first and the ticket last")
	func defaultTemplate() {
		let name = BranchNameFormatter.branchName(
			ticketId: "MOB-3752",
			summary: "EventList: HashMap concurrent read race",
			template: template
		)
		#expect(name == "eventlist_hashmap_concurrent_read_race_MOB-3752")
	}

	@Test("the row reads a generated name back as the summary, whatever the prefix")
	func roundTripsThroughFormat() {
		for template in [template, "bugfix/{summary}_{ticket}", "{ticket}_{summary}"] {
			let name = BranchNameFormatter.branchName(
				ticketId: "MOB-12",
				summary: "Fix login crash",
				template: template
			)
			let shown = BranchNameFormatter.format(name, ticketId: "MOB-12", branchNameRegex: "[a-zA-Z]+-\\d+[_/]")
			#expect(shown == "fix login crash", "template \(template) gave \(name)")
		}
	}

	@Test("diacritics are folded rather than dropped")
	func foldsDiacritics() {
		#expect(BranchNameFormatter.summarySlug("Oprava přihlášení – Žluťoučký kůň") == "oprava_prihlaseni_zlutoucky_kun")
	}

	@Test("punctuation and runs of separators collapse into single underscores")
	func collapsesSeparators() {
		#expect(BranchNameFormatter.summarySlug("  [iOS]  Crash -- in   \"Detail\"/tabs!! ") == "ios_crash_in_detail_tabs")
	}

	@Test("long summaries are cut at a word boundary")
	func cutsAtWordBoundary() {
		let slug = BranchNameFormatter.summarySlug(
			"Investigate why the event detail screen crashes when the koin module is reset during navigation"
		)
		#expect(slug.count <= BranchNameFormatter.maxSummarySlugLength)
		#expect(slug == "investigate_why_the_event_detail_screen_crashes")
	}

	@Test("a single over-long word is truncated, not dropped")
	func truncatesSingleLongWord() {
		let slug = BranchNameFormatter.summarySlug(String(repeating: "a", count: 80))
		#expect(slug == String(repeating: "a", count: BranchNameFormatter.maxSummarySlugLength))
	}

	@Test("an empty summary leaves no dangling separator")
	func emptySummary() {
		#expect(BranchNameFormatter.branchName(ticketId: "MOB-1", summary: "???", template: template) == "MOB-1")
		#expect(
			BranchNameFormatter.branchName(ticketId: "MOB-1", summary: "", template: "feature/{summary}_{ticket}")
				== "feature/MOB-1"
		)
		#expect(
			BranchNameFormatter.branchName(ticketId: "MOB-1", summary: "", template: "feature/{ticket}_{summary}")
				== "feature/MOB-1"
		)
	}

	@Test("a blank template falls back to the default")
	func blankTemplate() {
		#expect(BranchNameFormatter.branchName(ticketId: "MOB-1", summary: "Fix it", template: "  ") == "fix_it_MOB-1")
	}
}

@Suite("Claude command")
struct ClaudeCommandTests {
	@Test("no prompt starts Claude bare")
	func bare() {
		#expect(ClaudeCommand.make(prompt: "") == "claude")
		#expect(ClaudeCommand.make(prompt: "  \n ") == "claude")
	}

	@Test("the prompt is one single-quoted argument, with quotes inside it escaped")
	func quotesPrompt() {
		#expect(ClaudeCommand.make(prompt: "Fix Martin's $HOME `bug`") == #"claude 'Fix Martin'\''s $HOME `bug`'"#)
	}

	@Test("line breaks become spaces so typing the command does not submit it early")
	func flattensNewlines() {
		#expect(ClaudeCommand.make(prompt: "first\nsecond\r\nthird") == "claude 'first second third'")
	}
}

@Suite("YouTrack issue search")
struct YouTrackIssueSearchTests {
	@Test("parses hits, marking resolved ones and dropping those without an id")
	func parsesHits() throws {
		let json = Data("""
		[
		  {"idReadable": "MOB-1", "summary": "Open one", "resolved": null, "$type": "Issue"},
		  {"idReadable": "MOB-2", "summary": "Done one", "resolved": 1727000000000, "$type": "Issue"},
		  {"summary": "No id", "$type": "Issue"}
		]
		""".utf8)
		#expect(try YouTrackService.parseIssueSearch(from: json) == [
			YouTrackIssueSummary(id: "MOB-1", summary: "Open one"),
			YouTrackIssueSummary(id: "MOB-2", summary: "Done one", isResolved: true),
		])
	}

	@Test("a blank query asks for the user's open tickets")
	func blankQueryUsesDefault() throws {
		let request = try #require(YouTrackService.issueSearchRequest(query: " ", base: "https://yt.example", authToken: "t"))
		let url = try #require(request.url)
		let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
		#expect(items.first { $0.name == "query" }?.value == YouTrackService.defaultIssueSearchQuery)
		#expect(request.url?.path == "/api/issues")
		#expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer t")
	}

	@Test("the query is percent-encoded, including '+' and '#'")
	func encodesQuery() throws {
		let request = try #require(
			YouTrackService.issueSearchRequest(query: "c++ #Unresolved", base: "https://yt.example/youtrack", authToken: "t")
		)
		let query = try #require(request.url?.query(percentEncoded: true))
		#expect(query.contains("query=c%2B%2B%20%23Unresolved"))
		#expect(request.url?.path == "/youtrack/api/issues")
	}
}
