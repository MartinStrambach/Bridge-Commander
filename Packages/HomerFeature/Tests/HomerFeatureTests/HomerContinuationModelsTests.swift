import Foundation
@testable import HomerFeature
import Testing

@Suite("Homer continuation models")
struct HomerContinuationModelsTests {
	/// The backend's `ContinuationListResponse`, shaped like the console's test fixture
	/// (`continuation-item.test.tsx`), with the fields the app does not read left in.
	private let listJSON = """
		{
		  "continuations": [
		    {
		      "id": 5,
		      "watchedProcessId": 12,
		      "status": "PENDING",
		      "agentName": "follow-up",
		      "resumeParam": "RESULT",
		      "params": { "TICKET": "MOB-1234", "TOKEN": "***" },
		      "originProcessId": 7,
		      "originAgentName": "starter",
		      "expiresAt": 1700086400,
		      "createdAt": 1700000000,
		      "firedAt": null,
		      "firedProcessId": null,
		      "error": null
		    },
		    {
		      "id": 6,
		      "watchedProcessId": 13,
		      "status": "FAILED",
		      "agentName": "crash-report",
		      "resumeParam": "RESULT",
		      "params": {},
		      "originProcessId": 8,
		      "originAgentName": "factory",
		      "createdAt": 1700000100,
		      "error": "Agent not found: crash-report"
		    },
		    {
		      "id": 7,
		      "watchedProcessId": 14,
		      "status": "DISPATCHED",
		      "agentName": "follow-up",
		      "resumeParam": "RESULT",
		      "params": {},
		      "originProcessId": 9,
		      "originAgentName": "starter",
		      "createdAt": 1700000200,
		      "firedAt": 1700000300,
		      "firedProcessId": 99
		    },
		    {
		      "id": 8,
		      "watchedProcessId": 15,
		      "status": "PARKED_BY_A_NEWER_SERVER",
		      "agentName": "follow-up",
		      "resumeParam": "RESULT",
		      "params": {},
		      "originProcessId": 10,
		      "originAgentName": "starter",
		      "createdAt": 1700000400
		    }
		  ]
		}
		"""

	@Test("a continuation list decodes, unknown fields and statuses included")
	func decodesList() throws {
		let list = try JSONDecoder().decode(HomerContinuationList.self, from: Data(listJSON.utf8))

		#expect(list.continuations.map(\.id) == [5, 6, 7, 8])
		#expect(list.continuations.map(\.status) == [.pending, .failed, .dispatched, .unknown])
		#expect(list.continuations[0] == HomerContinuation(
			id: 5,
			watchedProcessId: 12,
			status: .pending,
			agentName: "follow-up",
			originProcessId: 7,
			originAgentName: "starter",
			expiresAt: 1_700_086_400,
			createdAt: 1_700_000_000
		))
		#expect(list.continuations[1].error == "Agent not found: crash-report")
		#expect(list.continuations[1].expiresAt == nil)
		#expect(list.continuations[2].firedProcessId == 99)
		#expect(list.continuations[2].firedAt == 1_700_000_300)
	}

	@Test("only a pending continuation offers Cancel")
	func cancellable() {
		let cancellable = HomerContinuationStatus.allCases.filter {
			HomerContinuation(
				id: 1,
				watchedProcessId: 2,
				status: $0,
				agentName: "a",
				originProcessId: 3,
				originAgentName: "b",
				createdAt: 0
			).isCancellable
		}

		#expect(cancellable == [.pending])
	}

	@Test("a run link in a card's text reads back as its process id")
	func processLink() throws {
		let url = try #require(HomerContinuationCard.processURL(42))

		#expect(HomerContinuationCard.processId(from: url) == 42)
		#expect(HomerContinuationCard.processId(from: URL(string: "https://homer.example.com/processes/42")!) == nil)
	}

	@Test("a stale cancel reads as the console's message, anything else as itself")
	func cancelErrors() {
		#expect(HomerContinuationsReducer.cancelErrorMessage(HomerAPIError.conflict)
			== HomerContinuationsReducer.notCancellableMessage)
		#expect(HomerContinuationsReducer.cancelErrorMessage(HomerAPIError.server(status: 404, message: "Not found"))
			== HomerContinuationsReducer.notCancellableMessage)
		#expect(HomerContinuationsReducer.cancelErrorMessage(HomerAPIError.forbidden)
			== HomerAPIError.forbidden.localizedDescription)
	}
}
