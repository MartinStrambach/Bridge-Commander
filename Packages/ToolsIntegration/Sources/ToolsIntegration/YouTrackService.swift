import Foundation

public nonisolated enum YouTrackService {
	private static let baseURL = "https://youtrack.livesport.eu/api"

	/// Fetches code review fields from a YouTrack issue
	/// - Parameters:
	///   - ticketId: The YouTrack ticket ID (e.g., "MOB-1963")
	///   - authToken: The YouTrack authentication token
	/// - Returns: A tuple containing (androidCR, iosCR, androidReviewerName, iosReviewerName, ticketState), any
	/// of which may be nil if not found
	public static func fetchIssueDetails(for ticketId: String, authToken: String) async
		-> (
			androidCR: CodeReviewState?,
			iosCR: CodeReviewState?,
			androidReviewerName: String?,
			iosReviewerName: String?,
			ticketState: TicketState?
		)
	{
		// Validate that a token is configured
		guard !authToken.isEmpty else {
			print("YouTrackService: Cannot fetch issue details without a valid auth token")
			return (nil, nil, nil, nil, nil)
		}

		let issueURL = "\(baseURL)/issues/\(ticketId)?fields=customFields(name,value(text,name))"

		guard let url = URL(string: issueURL) else {
			return (nil, nil, nil, nil, nil)
		}

		var request = URLRequest(url: url)
		request.httpMethod = "GET"
		request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
		request.setValue("application/json", forHTTPHeaderField: "Accept")

		do {
			print("YouTrackService: Fetching \(issueURL)")
			let (data, response) = try await URLSession.shared.data(for: request)

			guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
				let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
				print("YouTrackService: Failed with status code \(statusCode)")
				return (nil, nil, nil, nil, nil)
			}

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

			return (androidCR, iosCR, androidReviewerName, iosReviewerName, ticketState)
		}
		catch {
			print("YouTrackService: Error decoding response: \(error)")
			return (nil, nil, nil, nil, nil)
		}
	}

	/// Extracts a custom field value by field name
	/// - Parameters:
	///   - issue: The YouTrack issue to search
	///   - fieldName: The name of the custom field to find
	/// - Returns: The field value as a string, or nil if not found
	private static func extractCustomFieldValue(from issue: YouTrackIssue, fieldName: String) -> String? {
		guard let customFields = issue.customFields else {
			return nil
		}

		for field in customFields {
			if
				field.name?.lowercased() == fieldName.lowercased(),
				let fieldValue = field.value?.text
			{
				return fieldValue
			}
		}

		return nil
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
	let name: String?
	let value: CustomFieldValue?
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
