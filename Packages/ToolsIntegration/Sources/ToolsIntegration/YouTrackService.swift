import Foundation

/// Thrown when a YouTrack fetch could not complete. Distinct from a completed
/// fetch of an issue that simply lacks the code-review fields, which returns
/// nils — only the latter means the ticket genuinely has nothing to show.
public nonisolated enum YouTrackServiceError: Error {
	case missingToken
	case invalidURL
	case httpFailure(statusCode: Int)
}

public nonisolated enum YouTrackService {
	private static let baseURL = "https://youtrack.livesport.eu/api"

	/// The `$type` YouTrack reports for a custom field driven by a state-machine workflow. Only
	/// these fields carry `possibleEvents`, and only they are written with an event.
	private static let stateMachineFieldType = "StateMachineIssueCustomField"

	/// Fetches code review fields from a YouTrack issue
	/// - Parameters:
	///   - ticketId: The YouTrack ticket ID (e.g., "MOB-1963")
	///   - authToken: The YouTrack authentication token
	/// - Returns: Details whose fields may individually be nil/empty if not found. An all-empty
	/// value is also returned for a 404 — the ticket does not exist.
	/// - Throws: when the answer is unknown (missing token, network, non-404 HTTP, decoding), so callers
	/// can keep last-known state rather than treating the ticket as field-less.
	public static func fetchIssueDetails(for ticketId: String, authToken: String) async throws -> IssueDetails {
		// Validate that a token is configured
		guard !authToken.isEmpty else {
			print("YouTrackService: Cannot fetch issue details without a valid auth token")
			throw YouTrackServiceError.missingToken
		}

		// `possibleEvents` rides along on the request that already reads State and the CR
		// fields, so offering state transitions costs no extra round trip per row.
		let issueURL =
			"\(baseURL)/issues/\(ticketId)?fields=customFields($type,id,name,value(text,name),possibleEvents(id,presentation))"

		guard let url = URL(string: issueURL) else {
			throw YouTrackServiceError.invalidURL
		}

		var request = URLRequest(url: url)
		request.httpMethod = "GET"
		request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
		request.setValue("application/json", forHTTPHeaderField: "Accept")

		print("YouTrackService: Fetching \(issueURL)")
		let (data, response) = try await URLSession.shared.data(for: request)

		guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
			let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
			if statusCode == 404 {
				// The ticket ID parsed from the branch has no matching issue —
				// a definitive answer, not a failure.
				print("YouTrackService: Issue \(ticketId) not found")
				return IssueDetails(
					androidCR: nil,
					iosCR: nil,
					androidReviewerName: nil,
					iosReviewerName: nil,
					ticketState: nil
				)
			}
			throw YouTrackServiceError.httpFailure(statusCode: statusCode)
		}

		return try parseIssueDetails(from: data)
	}

	/// Decodes an issue payload into ``IssueDetails``. Split out from the request so the field
	/// extraction can be exercised without a network round trip.
	public static func parseIssueDetails(from data: Data) throws -> IssueDetails {
		let decoder = JSONDecoder()
		let issue = try decoder.decode(YouTrackIssue.self, from: data)
		print("YouTrackService: Successfully fetched issue \(issue.key ?? "unknown")")

		let androidCRString = extractCustomFieldValue(from: issue, fieldName: "Android CR")
		let androidCR = androidCRString.flatMap { CodeReviewState(rawValue: $0) }
		let iosCRString = extractCustomFieldValue(from: issue, fieldName: "iOS CR")
		let iosCR = iosCRString.flatMap { CodeReviewState(rawValue: $0) }
		let androidReviewerName = extractCustomFieldValue(from: issue, fieldName: "Android CR Assignee")
		let iosReviewerName = extractCustomFieldValue(from: issue, fieldName: "iOS CR Assignee")
		let ticketStateString = extractCustomFieldValue(from: issue, fieldName: "State")
		let ticketState = ticketStateString.flatMap { TicketState(rawValue: $0) }

		let stateField = findCustomField(in: issue, named: "State")
		// A plain StateIssueCustomField reports no events, and YouTrack exposes no other
		// reachability answer — leave the list empty rather than offering every bundle value.
		let stateTransitions =
			if stateField?.type == stateMachineFieldType {
				(stateField?.possibleEvents ?? []).compactMap { event -> TicketStateTransition? in
					guard let eventId = event.id, let presentation = event.presentation else {
						return nil
					}
					return TicketStateTransition(eventId: eventId, presentation: presentation)
				}
			}
			else {
				[TicketStateTransition]()
			}

		if let androidCRString {
			print("YouTrackService: Found Android CR: \(androidCRString) -> \(androidCR?.rawValue ?? "unknown")")
		}
		if let iosCRString {
			print("YouTrackService: Found iOS CR: \(iosCRString) -> \(iosCR?.rawValue ?? "unknown")")
		}
		if let androidReviewerName {
			print("YouTrackService: Found Android CR Assignee: \(androidReviewerName)")
		}
		if let iosReviewerName {
			print("YouTrackService: Found iOS CR Assignee: \(iosReviewerName)")
		}
		if let ticketStateString {
			print("YouTrackService: Found State: \(ticketStateString) -> \(ticketState?.rawValue ?? "unknown")")
		}
		if !stateTransitions.isEmpty {
			print("YouTrackService: Reachable states: \(stateTransitions.map(\.presentation).joined(separator: ", "))")
		}

		return IssueDetails(
			androidCR: androidCR,
			iosCR: iosCR,
			androidReviewerName: androidReviewerName,
			iosReviewerName: iosReviewerName,
			ticketState: ticketState,
			stateFieldId: stateField?.id,
			stateTransitions: stateTransitions
		)
	}

	/// Moves an issue's state-machine field by sending one of its `possibleEvents`.
	///
	/// State-machine fields ignore a plain `value` write, so the transition is expressed as an
	/// event id taken from ``IssueDetails/stateTransitions``.
	/// - Throws: when the token is missing, the URL is malformed, or YouTrack rejects the event.
	public static func applyStateEvent(
		for ticketId: String,
		fieldId: String,
		eventId: String,
		authToken: String
	) async throws {
		guard !authToken.isEmpty else {
			print("YouTrackService: Cannot change state without a valid auth token")
			throw YouTrackServiceError.missingToken
		}

		guard let url = URL(string: "\(baseURL)/issues/\(ticketId)/customFields/\(fieldId)") else {
			throw YouTrackServiceError.invalidURL
		}

		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
		request.setValue("application/json", forHTTPHeaderField: "Accept")
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.httpBody = try JSONSerialization.data(withJSONObject: [
			"$type": stateMachineFieldType,
			"id": fieldId,
			"event": ["$type": "Event", "id": eventId],
		])

		print("YouTrackService: Sending event '\(eventId)' to \(ticketId) field \(fieldId)")
		let (_, response) = try await URLSession.shared.data(for: request)

		guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
			let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
			throw YouTrackServiceError.httpFailure(statusCode: statusCode)
		}
	}

	/// Finds a custom field by name, case-insensitively.
	private static func findCustomField(in issue: YouTrackIssue, named fieldName: String) -> CustomField? {
		issue.customFields?.first { $0.name?.lowercased() == fieldName.lowercased() }
	}

	/// Extracts a custom field value by field name
	/// - Parameters:
	///   - issue: The YouTrack issue to search
	///   - fieldName: The name of the custom field to find
	/// - Returns: The field value as a string, or nil if not found
	private static func extractCustomFieldValue(from issue: YouTrackIssue, fieldName: String) -> String? {
		findCustomField(in: issue, named: fieldName)?.value?.text
	}
}

// MARK: - YouTrack API Response Models

private nonisolated struct YouTrackIssue: Decodable {
	enum CodingKeys: String, CodingKey {
		case id
		case key
		case customFields
	}

	let id: String?
	let key: String?
	let customFields: [CustomField]?
}

private struct CustomField: Decodable {
	enum CodingKeys: String, CodingKey {
		case id
		case name
		case value
		case possibleEvents
		case type = "$type"
	}

	let id: String?
	let name: String?
	let value: CustomFieldValue?
	/// Present only on state-machine fields: the transitions legal from the current value.
	let possibleEvents: [PossibleEvent]?
	let type: String?
}

private struct PossibleEvent: Decodable {
	let id: String?
	let presentation: String?
}

private struct CustomFieldValue: Decodable {
	enum CodingKeys: String, CodingKey {
		case text
		case name
		case _type = "$type"
	}

	let text: String?

	init(from decoder: Decoder) throws {
		let container = try? decoder.container(keyedBy: CodingKeys.self)

		// Get the type field to determine which property to extract
		let typeValue = try (container?.decodeIfPresent(String.self, forKey: ._type)) ?? ""

		// Parse based on type - extract the appropriate property
		if typeValue.contains("TextFieldValue") {
			self.text = try container?.decodeIfPresent(String.self, forKey: .text)
		}
		else if
			typeValue.contains("User") || typeValue.contains("EnumBundleElement") || typeValue
				.contains("StateBundleElement")
		{
			self.text = try container?.decodeIfPresent(String.self, forKey: .name)
		}
		else {
			self.text = nil
		}
	}
}
