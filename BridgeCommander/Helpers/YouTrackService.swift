import Foundation

enum YouTrackService {
	private static let baseURL = "https://youtrack.livesport.eu/api"

	/// Gets the auth token from UserDefaults
	private static var authToken: String {
		UserDefaults.standard.string(forKey: "youtrackAuthToken") ?? ""
	}

	/// Fetches PR URL and code review fields from a YouTrack issue
	/// - Parameter ticketId: The YouTrack ticket ID (e.g., "MOB-1963")
	/// - Returns: A tuple containing (prUrl, androidCR, iosCR, androidReviewerName, iosReviewerName), any of which may
	/// be nil if not found
	static func fetchIssueDetails(for ticketId: String) async
		-> (
			prUrl: String?,
			androidCR: String?,
			iosCR: String?,
			androidReviewerName: String?,
			iosReviewerName: String?
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

			let prUrl = extractMonorepoPRUrl(from: issue)
			let androidCR = extractCustomFieldValue(from: issue, fieldName: "Android CR")
			let iosCR = extractCustomFieldValue(from: issue, fieldName: "iOS CR")
			let androidReviewerName = extractCustomFieldValue(from: issue, fieldName: "Android CR Assignee")
			let iosReviewerName = extractCustomFieldValue(from: issue, fieldName: "iOS CR Assignee")

			if let prUrl {
				print("YouTrackService: Found Monorepo PR: \(prUrl)")
			}
			else {
				print("YouTrackService: No Monorepo PR found")
			}
			if let androidCR {
				print("YouTrackService: Found Android CR: \(androidCR)")
			}
			if let iosCR {
				print("YouTrackService: Found iOS CR: \(iosCR)")
			}
			if let androidReviewerName {
				print("YouTrackService: Found Android CR Assignee: \(androidReviewerName)")
			}
			if let iosReviewerName {
				print("YouTrackService: Found iOS CR Assignee: \(iosReviewerName)")
			}

			return (prUrl, androidCR, iosCR, androidReviewerName, iosReviewerName)
		}
		catch {
			print("YouTrackService: Error decoding response: \(error)")
			return (nil, nil, nil, nil, nil)
		}
	}

	/// Extracts the Monorepo PR URL from the YouTrack issue's custom fields
	/// - Parameter issue: The decoded YouTrack issue
	/// - Returns: The PR URL, or nil if not found
	private static func extractMonorepoPRUrl(from issue: YouTrackIssue) -> String? {
		guard let customFields = issue.customFields else {
			return nil
		}

		for field in customFields {
			// Look for field named "Code review urls"
			if
				field.name?.lowercased() == "code review urls",
				let fieldText = field.value?.text
			{
				// Extract the Monorepo PR URL from the field text
				if let prUrl = extractMonorepoPRFromText(fieldText) {
					return prUrl
				}
			}
		}

		return nil
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

	/// Extracts the Monorepo PR URL from Code review urls field text
	/// - Parameter fieldText: The text content of the Code review urls field
	/// - Returns: The Monorepo PR URL, or nil if not found
	private static func extractMonorepoPRFromText(_ fieldText: String) -> String? {
		// The field may contain multiple lines like:
		// Monorepo: https://github.com/...
		// Android: https://github.com/...
		// iOS: https://github.com/...

		let lines = fieldText.split(separator: "\n", omittingEmptySubsequences: true)

		for line in lines {
			let trimmedLine = line.trimmingCharacters(in: .whitespaces)

			// Look for lines starting with "Monorepo:"
			if trimmedLine.lowercased().hasPrefix("monorepo:") {
				// Extract URL from this line
				if let url = extractUrlFromText(String(trimmedLine)) {
					return url
				}
			}
		}

		return nil
	}

	/// Extracts the actual URL from a text that may contain prefix like "Monorepo: <url>"
	/// - Parameter text: The text that may contain a URL
	/// - Returns: The extracted URL, or nil if not found
	private static func extractUrlFromText(_ text: String) -> String? {
		// Try to extract URL pattern: http(s)://...
		// Match http(s) followed by any non-whitespace characters (greedy)
		let pattern = "https?://\\S+"
		if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
			let range = NSRange(text.startIndex..., in: text)
			if
				let match = regex.firstMatch(in: text, options: [], range: range),
				let urlRange = Range(match.range, in: text)
			{
				return String(text[urlRange])
			}
		}
		return nil
	}
}

// MARK: - YouTrack API Response Models

struct YouTrackIssue: Decodable {
	enum CodingKeys: String, CodingKey {
		case id
		case key
		case customFields
	}

	let id: String?
	let key: String?
	let customFields: [CustomField]?

}

struct CustomField: Decodable {
	let name: String?
	let value: CustomFieldValue?
}

struct CustomFieldValue: Decodable {
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
		else if typeValue.contains("User") || typeValue.contains("EnumBundleElement") {
			self.text = try container?.decodeIfPresent(String.self, forKey: .name)
		}
		else {
			self.text = nil
		}
	}

}
