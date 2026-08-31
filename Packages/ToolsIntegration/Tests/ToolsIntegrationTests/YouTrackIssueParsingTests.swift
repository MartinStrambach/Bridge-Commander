import Foundation
import Testing
@testable import ToolsIntegration

@Suite("YouTrack issue parsing")
struct YouTrackIssueParsingTests {
	/// Shape captured from a real YouTrack response for an issue in "In Progress".
	private let stateMachineIssue = Data("""
	{
	  "id": "3-12345",
	  "key": "MOB-4039",
	  "customFields": [
	    {
	      "name": "Assignee",
	      "id": "93-208",
	      "$type": "SingleUserIssueCustomField",
	      "value": { "name": "Martin Strambach", "$type": "User" }
	    },
	    {
	      "name": "Ready for dev",
	      "id": "84-952",
	      "$type": "MultiEnumIssueCustomField",
	      "value": [
	        { "name": "Test OK", "$type": "EnumBundleElement" },
	        { "name": "Dev OK", "$type": "EnumBundleElement" }
	      ]
	    },
	    {
	      "name": "Android CR",
	      "id": "84-965",
	      "$type": "StateMachineIssueCustomField",
	      "value": { "name": "Waiting", "$type": "EnumBundleElement" },
	      "possibleEvents": [{ "presentation": "Passed", "id": "cr ok", "$type": "Event" }]
	    },
	    {
	      "name": "iOS CR Assignee",
	      "id": "93-211",
	      "$type": "SingleUserIssueCustomField",
	      "value": { "name": "Bob", "$type": "User" }
	    },
	    {
	      "name": "State",
	      "id": "84-950",
	      "$type": "StateMachineIssueCustomField",
	      "value": { "name": "In Progress", "id": "59-1190", "$type": "StateBundleElement" },
	      "possibleEvents": [
	        { "presentation": "Waiting to code review", "id": "to review", "$type": "Event" },
	        { "presentation": "Waiting for testing", "id": "test feature-bug", "$type": "Event" },
	        { "presentation": "Open", "id": "reopen", "$type": "Event" },
	        { "presentation": "Done", "id": "done", "$type": "Event" }
	      ]
	    }
	  ]
	}
	""".utf8)

	@Test("a state-machine State field yields its reachable transitions and field id")
	func parsesReachableTransitions() throws {
		let details = try YouTrackService.parseIssueDetails(from: stateMachineIssue)

		#expect(details.ticketState == .inProgress)
		#expect(details.stateFieldId == "84-950")
		#expect(details.stateTransitions == [
			TicketStateTransition(eventId: "to review", presentation: "Waiting to code review"),
			TicketStateTransition(eventId: "test feature-bug", presentation: "Waiting for testing"),
			TicketStateTransition(eventId: "reopen", presentation: "Open"),
			TicketStateTransition(eventId: "done", presentation: "Done"),
		])
	}

	@Test("widening the request for possibleEvents leaves the existing fields intact")
	func stillParsesCodeReviewFields() throws {
		let details = try YouTrackService.parseIssueDetails(from: stateMachineIssue)

		#expect(details.androidCR == .waiting)
		#expect(details.iosReviewerName == "Bob")
		#expect(details.iosCR == nil)
		#expect(details.androidReviewerName == nil)
	}

	@Test("presentations outside the TicketState enum are still offered")
	func keepsUnmodelledPresentations() throws {
		let json = Data("""
		{
		  "key": "MOB-4432",
		  "customFields": [{
		    "name": "State",
		    "id": "84-950",
		    "$type": "StateMachineIssueCustomField",
		    "value": { "name": "Open", "$type": "StateBundleElement" },
		    "possibleEvents": [
		      { "presentation": "In Progress", "id": "take", "$type": "Event" },
		      { "presentation": "Duplicate", "id": "duplicate", "$type": "Event" },
		      { "presentation": "Invalid", "id": "invalid", "$type": "Event" }
		    ]
		  }]
		}
		""".utf8)

		let details = try YouTrackService.parseIssueDetails(from: json)

		// Duplicate and Invalid have no TicketState case; the menu shows YouTrack's own label.
		#expect(details.stateTransitions.map(\.presentation) == ["In Progress", "Duplicate", "Invalid"])
	}

	@Test("a State field without a state machine reports no transitions")
	func plainStateFieldHasNoTransitions() throws {
		let json = Data("""
		{
		  "key": "ABC-1",
		  "customFields": [{
		    "name": "State",
		    "id": "84-111",
		    "$type": "StateIssueCustomField",
		    "value": { "name": "Open", "$type": "StateBundleElement" }
		  }]
		}
		""".utf8)

		let details = try YouTrackService.parseIssueDetails(from: json)

		#expect(details.ticketState == .open)
		#expect(details.stateFieldId == "84-111")
		// Reachability is unknown without a state machine, so nothing is offered.
		#expect(details.stateTransitions.isEmpty)
	}

	@Test("an issue with no State field yields no field id and no transitions")
	func missingStateField() throws {
		let json = Data("""
		{ "key": "ABC-2", "customFields": [] }
		""".utf8)

		let details = try YouTrackService.parseIssueDetails(from: json)

		#expect(details.ticketState == nil)
		#expect(details.stateFieldId == nil)
		#expect(details.stateTransitions.isEmpty)
	}
}
