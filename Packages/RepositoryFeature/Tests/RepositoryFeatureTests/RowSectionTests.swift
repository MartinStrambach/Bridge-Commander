import ComposableArchitecture
import Settings
import Testing
import ToolsIntegration
@testable import RepositoryFeature

// The list splits a group's worktrees under headers instead of tinting each row. What they split on
// follows the sort: `TicketStateSection` is what sorting by state and its headers agree on, and
// sorting by ticket splits per ticket. Headers mark contiguous runs, so they describe the order the
// rows are actually in.
@Suite("Row sections")
@MainActor
struct RowSectionTests {
	// MARK: - Ticket state sections

	@Test("a row without a ticket falls outside every state")
	func rowWithoutTicketHasNoSection() {
		#expect(TicketStateSection(row: row("/w/none")) == .noTicket)
	}

	@Test("a ticket whose state hasn't been fetched sits in its own section")
	func rowWithUnfetchedStateHasOwnSection() {
		#expect(TicketStateSection(row: row("/w/a", ticket: "MOB-1")) == .unknownState)
	}

	@Test("every YouTrack state maps to its own section")
	func everyStateMaps() {
		let expected: [(TicketState, TicketStateSection)] = [
			(.open, .open),
			(.inProgress, .inProgress),
			(.waitingToCodeReview, .waitingToCodeReview),
			(.waitingForTesting, .waitingForTesting),
			(.waitingToAcceptation, .waitingToAcceptation),
			(.accepted, .accepted),
			(.done, .done),
		]
		for (state, section) in expected {
			#expect(TicketStateSection(row: row("/w/a", ticket: "MOB-1", state: state)) == section)
		}
	}

	@Test("sections order unstarted work first and finished work last")
	func sectionsAreOrdered() {
		let ordered: [TicketStateSection] = [
			.noTicket,
			.open,
			.inProgress,
			.waitingToCodeReview,
			.waitingForTesting,
			.unknownState,
			.waitingToAcceptation,
			.accepted,
			.done,
		]
		#expect(ordered.sorted() == ordered)
	}

	// MARK: - Headers while sorting by state

	@Test("each run of same-state rows gets one header, counting the rows below it")
	func headersIntroduceEachRun() {
		let group = group(rows: [
			row("/w/a", ticket: "MOB-3", state: .inProgress),
			row("/w/b", ticket: "MOB-2", state: .inProgress),
			row("/w/c", ticket: "MOB-1", state: .done),
		])

		#expect(group.sectionHeaders(sortMode: .state, visibility: .unfiltered) == [
			"/w/a": RowSectionHeader(section: .ticketState(.inProgress), count: 2),
			"/w/c": RowSectionHeader(section: .ticketState(.done), count: 1),
		])
	}

	@Test("headers describe the rows the filter reveals, not the ones it hides")
	func headersCountOnlyVisibleRows() {
		let group = group(rows: [
			row("/w/a", ticket: "MOB-3", state: .inProgress),
			row("/w/b", ticket: "MOB-2", state: .inProgress),
			row("/w/c", ticket: "MOB-1", state: .done),
		])

		// Hiding the run's first row moves its header onto the next one.
		#expect(group.sectionHeaders(sortMode: .state, visibility: .worktrees(["/w/b", "/w/c"])) == [
			"/w/b": RowSectionHeader(section: .ticketState(.inProgress), count: 1),
			"/w/c": RowSectionHeader(section: .ticketState(.done), count: 1),
		])
	}

	@Test("a row sorted out of place repeats its header rather than sitting under a wrong one")
	func outOfOrderRowRepeatsItsHeader() {
		// What a just-fetched state looks like before the debounced re-sort lands.
		let group = group(rows: [
			row("/w/a", ticket: "MOB-3", state: .inProgress),
			row("/w/b", ticket: "MOB-2", state: .done),
			row("/w/c", ticket: "MOB-1", state: .inProgress),
		])

		#expect(group.sectionHeaders(sortMode: .state, visibility: .unfiltered) == [
			"/w/a": RowSectionHeader(section: .ticketState(.inProgress), count: 1),
			"/w/b": RowSectionHeader(section: .ticketState(.done), count: 1),
			"/w/c": RowSectionHeader(section: .ticketState(.inProgress), count: 1),
		])
	}

	@Test("a group with no worktrees needs no headers")
	func emptyGroupHasNoHeaders() {
		#expect(group(rows: []).sectionHeaders(sortMode: .state, visibility: .unfiltered).isEmpty)
	}

	@Test("a group without a ticket regex draws no headers")
	func groupWithoutTicketRegexHasNoHeaders() {
		// Ticket parsing is off for the whole group, so a "No ticket" header would state a fact
		// about the branches that is really a fact about the configuration.
		let group = group(
			rows: [row("/w/a"), row("/w/b")],
			ticketIdRegex: ""
		)

		#expect(group.sectionHeaders(sortMode: .state, visibility: .unfiltered).isEmpty)
		#expect(group.sectionHeaders(sortMode: .ticket, visibility: .unfiltered).isEmpty)
	}

	// MARK: - Headers while sorting by ticket

	@Test("sorting by ticket splits the rows into one ticketed and one ticketless section")
	func ticketSortSplitsOnHavingATicket() {
		let group = group(rows: [
			row("/w/a", ticket: "MOB-2", state: .inProgress),
			row("/w/b", ticket: "MOB-1", state: .done),
			row("/w/c"),
			row("/w/d"),
		])

		// Every ticket shares one header — neither a differing ticket nor a differing state splits
		// the rows further.
		let headers = group.sectionHeaders(sortMode: .ticket, visibility: .unfiltered)

		#expect(headers == [
			"/w/a": RowSectionHeader(section: .tickets, count: 2),
			"/w/c": RowSectionHeader(section: .noTicket, count: 2),
		])
		#expect(headers["/w/a"]?.section.title == "Tickets")
		#expect(headers["/w/c"]?.section.title == "No ticket")
	}

	// MARK: - Headers while sorting by branch

	@Test("sorting by branch draws no headers")
	func branchSortHasNoHeaders() {
		let group = group(rows: [
			row("/w/a", ticket: "MOB-2", state: .inProgress),
			row("/w/b", ticket: "MOB-1", state: .done),
			row("/w/c"),
		])

		#expect(group.sectionHeaders(sortMode: .branch, visibility: .unfiltered).isEmpty)
	}

	// MARK: - Helpers

	private func row(
		_ path: String,
		ticket: String? = nil,
		state: TicketState? = nil
	) -> RepositoryRowReducer.State {
		var row = RepositoryRowReducer.State(
			path: path,
			name: path,
			branchName: "branch",
			isWorktree: true
		)
		row.ticketId = ticket
		row.ticketState = state
		return row
	}

	private func group(
		rows: [RepositoryRowReducer.State],
		ticketIdRegex: String = "MOB-[0-9]+"
	) -> RepoGroupReducer.State {
		RepoGroupReducer.State(
			id: "/repos/alpha",
			isCollapsed: false,
			header: row("/repos/alpha"),
			worktrees: IdentifiedArrayOf(uniqueElements: rows),
			settings: RepoGroupSettings(ticketIdRegex: ticketIdRegex)
		)
	}
}
