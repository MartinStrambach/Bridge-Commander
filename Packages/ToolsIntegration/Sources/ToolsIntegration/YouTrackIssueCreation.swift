import ActivityLog
import Foundation

/// A project new tickets can be filed in.
public nonisolated struct YouTrackProject: Equatable, Sendable, Identifiable {
	/// The database id (`0-1`): what `POST /api/issues` takes, not the short name.
	public let id: String
	/// The ticket prefix (`MOB`).
	public let shortName: String
	public let name: String

	public init(id: String, shortName: String, name: String) {
		self.id = id
		self.shortName = shortName
		self.name = name
	}
}

/// When YouTrack shows a conditional field: only while another field holds one of `values`. A
/// hidden field is left out of the ticket's fields altogether, so it cannot be set.
public nonisolated struct YouTrackFieldCondition: Equatable, Sendable {
	/// The name of the field the condition reads.
	public let field: String
	public let values: [String]

	public init(field: String, values: [String]) {
		self.field = field
		self.values = values
	}
}

/// One of a project's choice fields — an enum, subsystem, version or build field — offered on a
/// new ticket. State fields and user fields are not among them.
public nonisolated struct YouTrackChoiceField: Equatable, Sendable, Identifiable {
	/// The field's name, unique within a project: what its value is matched by on the new ticket.
	public let name: String
	/// Its values, archived ones left out, in the project's order.
	public let values: [String]
	/// What YouTrack fills in on a new ticket that names nothing.
	public let defaultValues: [String]
	public let isMultiValue: Bool
	/// Whether the field may be left without a value.
	public let canBeEmpty: Bool
	/// Whether a state-machine workflow drives the field, so its `values` after the starting one
	/// are the events YouTrack offers from it ("needed"), not the values they lead to.
	public let eventDriven: Bool
	/// Nil for a field YouTrack always shows.
	public let condition: YouTrackFieldCondition?

	public var id: String { name }

	public init(
		name: String,
		values: [String],
		defaultValues: [String],
		isMultiValue: Bool,
		canBeEmpty: Bool,
		eventDriven: Bool = false,
		condition: YouTrackFieldCondition? = nil
	) {
		self.name = name
		self.values = values
		self.defaultValues = defaultValues
		self.isMultiValue = isMultiValue
		self.canBeEmpty = canBeEmpty
		self.eventDriven = eventDriven
		self.condition = condition
	}
}

/// What a new ticket in one project can be filled in with.
public nonisolated struct YouTrackProjectFields: Equatable, Sendable {
	/// The project's choice fields, in the project's order.
	public let choiceFields: [YouTrackChoiceField]
	/// Logins the project's Assignee field accepts, or nil when it has no Assignee field (matched
	/// by YouTrack's default name).
	public let assignableLogins: Set<String>?
	/// What every field of the project, choice or not, holds on a new ticket, by name: what a
	/// condition on a field that is not offered (State) reads.
	public let initialValues: [String: [String]]
	/// The name of the project's State field, or nil when it has none.
	public let stateFieldName: String?

	public init(
		choiceFields: [YouTrackChoiceField],
		assignableLogins: Set<String>?,
		initialValues: [String: [String]] = [:],
		stateFieldName: String? = nil
	) {
		self.choiceFields = choiceFields
		self.assignableLogins = assignableLogins
		self.initialValues = initialValues
		self.stateFieldName = stateFieldName
	}

	public func canAssign(_ login: String) -> Bool {
		assignableLogins?.contains(login) ?? false
	}

	/// Whether YouTrack shows `field` on a ticket whose fields hold `values` (by name); a field
	/// `values` does not name holds its ``initialValues``.
	public func shows(_ field: YouTrackChoiceField, values: [String: [String]]) -> Bool {
		guard let condition = field.condition else {
			return true
		}
		let controlling = values[condition.field] ?? initialValues[condition.field] ?? []
		return controlling.contains(where: condition.values.contains)
	}
}

/// A value picked for one of a new ticket's choice fields; empty `values` clears the field.
public nonisolated struct YouTrackFieldValue: Equatable, Sendable {
	public let field: String
	public let values: [String]

	public init(field: String, values: [String]) {
		self.field = field
		self.values = values
	}
}

/// What a new ticket is filed with.
public nonisolated struct NewYouTrackIssue: Equatable, Sendable {
	public let projectId: String
	public let summary: String
	public let description: String
	/// Must be one of the project's ``YouTrackProjectFields/assignableLogins`` — YouTrack rejects
	/// the whole ticket otherwise.
	public let assigneeLogin: String?
	/// Set once the ticket exists (``YouTrackService/applyFieldValues(_:to:baseURL:authToken:)``),
	/// not in the create itself.
	public let fieldValues: [YouTrackFieldValue]

	public init(
		projectId: String,
		summary: String,
		description: String,
		assigneeLogin: String?,
		fieldValues: [YouTrackFieldValue] = []
	) {
		self.projectId = projectId
		self.summary = summary
		self.description = description
		self.assigneeLogin = assigneeLogin
		self.fieldValues = fieldValues
	}
}

/// How one picked value reaches a filed ticket.
nonisolated enum YouTrackFieldUpdate: Equatable {
	/// A field driven by a state-machine workflow only changes through one of its events.
	case event(field: String, fieldId: String, eventId: String)
	/// Any other field is written directly, with the issue field type YouTrack reported for it.
	case set(field: String, fieldId: String, issueFieldType: String, values: [String], isMultiValue: Bool)
	/// The ticket does not show the field (yet): a conditional field whose condition does not hold.
	case hidden(field: String)
	/// Cannot be set; the reason is shown to the user.
	case impossible(field: String, reason: String)
}

public nonisolated extension YouTrackService {
	/// The bundles whose fields are offered as choices on a new ticket. `StateBundle` is left to
	/// the In Progress transition, `UserBundle` to Assign to me.
	private static let choiceBundleTypes: Set<String> = ["EnumBundle", "OwnedBundle", "VersionBundle", "BuildBundle"]

	/// How many recent tickets are read for the events a new ticket's workflow fields offer.
	private static let workflowSampleSize = 50

	/// The name of the field a new ticket is assigned with.
	static let assigneeFieldName = "Assignee"

	/// Lists the projects the token can read, archived ones left out, sorted by short name.
	static func listProjects(baseURL: String, authToken: String) async throws -> [YouTrackProject] {
		let request = try authorizedRequest(
			path: "/api/admin/projects",
			query: [
				URLQueryItem(name: "fields", value: "id,shortName,name,archived"),
				URLQueryItem(name: "$top", value: "1000"),
			],
			baseURL: baseURL,
			authToken: authToken
		)
		return try parseProjects(from: try await send(request))
	}

	/// Reads one project's choice fields and its Assignee field's users. A field a state-machine
	/// workflow drives offers the events YouTrack lists from a new ticket's starting value, read
	/// from the project's recent tickets; without such a ticket it offers its values.
	static func projectFields(project: YouTrackProject, baseURL: String, authToken: String) async throws -> YouTrackProjectFields {
		let request = try authorizedRequest(
			path: "/api/admin/projects/\(project.id)/customFields",
			query: [
				URLQueryItem(
					name: "fields",
					value: "$type,canBeEmpty,field(name,fieldType(isMultiValue)),defaultValues(name),"
						+ "bundle($type,values(name,archived),aggregatedUsers(login)),condition(field(field(name)),values(name))"
				),
				URLQueryItem(name: "$top", value: "500"),
			],
			baseURL: baseURL,
			authToken: authToken
		)
		let fields = try parseProjectFields(from: try await send(request))
		let samples = try? authorizedRequest(
			path: "/api/issues",
			query: [
				URLQueryItem(name: "query", value: "project: {\(project.shortName)} sort by: created desc"),
				URLQueryItem(name: "fields", value: "customFields($type,name,value(name),possibleEvents(id,presentation))"),
				URLQueryItem(name: "$top", value: "\(workflowSampleSize)"),
			],
			baseURL: baseURL,
			authToken: authToken
		)
		guard let samples, let data = try? await send(samples) else {
			return fields
		}
		return (try? applyingWorkflowEvents(to: fields, sampleIssues: data)) ?? fields
	}

	/// Files a new ticket with its summary, description and assignee; its
	/// ``NewYouTrackIssue/fieldValues`` are set afterwards with
	/// ``applyFieldValues(_:to:baseURL:authToken:)``.
	/// - Returns: the ticket as YouTrack numbered it.
	/// - Throws: when the token or base URL is missing, the URL is malformed, or YouTrack refuses
	/// the ticket (403 without the right to create issues in the project, 400 for a field value
	/// it does not accept).
	static func createIssue(_ issue: NewYouTrackIssue, baseURL: String, authToken: String) async throws -> YouTrackIssueSummary {
		var request = try authorizedRequest(
			path: "/api/issues",
			query: [URLQueryItem(name: "fields", value: "idReadable,summary")],
			baseURL: baseURL,
			authToken: authToken
		)
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.httpBody = try createIssueBody(issue)

		print("YouTrackService: Creating issue in project \(issue.projectId)")
		return try parseCreatedIssue(from: try await send(request))
	}

	/// Sets picked choice values on a filed ticket, each the way its field takes it: a
	/// state-machine field through the event YouTrack presents as the value, any other directly.
	/// Values the ticket already has are skipped. One field failing does not stop the others. A
	/// conditional field the ticket does not show is tried again after the others, as long as
	/// setting them changed something: one of them may be what shows it (Type → Detected in).
	/// - Returns: a line per field that could not be set.
	/// - Throws: only when the ticket's fields cannot be read at all.
	static func applyFieldValues(
		_ values: [YouTrackFieldValue],
		to ticketId: String,
		baseURL: String,
		authToken: String
	) async throws -> [String] {
		guard !values.isEmpty else {
			return []
		}
		var pending = values
		var failures: [String] = []
		while true {
			let request = try authorizedRequest(
				path: "/api/issues/\(ticketId)",
				query: [URLQueryItem(
					name: "fields",
					value: "customFields($type,id,name,value(name),possibleEvents(id,presentation))"
				)],
				baseURL: baseURL,
				authToken: authToken
			)
			let updates = try fieldUpdates(for: pending, issue: try await send(request))

			var hidden: [YouTrackFieldValue] = []
			var changedSomething = false
			for update in updates {
				do {
					switch update {
					case let .event(_, fieldId, eventId):
						try await applyStateEvent(
							for: ticketId,
							fieldId: fieldId,
							eventId: eventId,
							baseURL: baseURL,
							authToken: authToken
						)
						changedSomething = true
					case let .set(_, fieldId, issueFieldType, values, isMultiValue):
						var request = try authorizedRequest(
							path: "/api/issues/\(ticketId)/customFields/\(fieldId)",
							query: [URLQueryItem(name: "fields", value: "id")],
							baseURL: baseURL,
							authToken: authToken
						)
						request.httpMethod = "POST"
						request.setValue("application/json", forHTTPHeaderField: "Content-Type")
						request.httpBody = try setFieldBody(type: issueFieldType, values: values, isMultiValue: isMultiValue)
						_ = try await send(request)
						changedSomething = true
					case let .hidden(field):
						hidden += pending.filter { $0.field == field }
					case let .impossible(field, reason):
						failures.append("\(field) was not set: \(reason)")
					}
				}
				catch {
					failures.append("\(update.field) was not set: \(error.localizedDescription)")
				}
			}
			guard !hidden.isEmpty, changedSomething else {
				failures += hidden.map { "\($0.field) was not set: \(hiddenFieldReason)" }
				break
			}
			pending = hidden
		}
		return failures
	}

	/// Internal so the JSON YouTrack receives is unit-testable.
	internal static func createIssueBody(_ issue: NewYouTrackIssue) throws -> Data {
		var body: [String: Any] = [
			"project": ["id": issue.projectId],
			"summary": issue.summary,
			"description": issue.description,
		]
		if let login = issue.assigneeLogin {
			body["customFields"] = [[
				"name": assigneeFieldName,
				"$type": "SingleUserIssueCustomField",
				"value": ["login": login],
			]]
		}
		return try JSONSerialization.data(withJSONObject: body, options: .sortedKeys)
	}

	/// Plans how each picked value reaches the ticket described by `issue` (its `customFields`).
	/// Internal so the matching is unit-testable from fixture JSON.
	internal static func fieldUpdates(for values: [YouTrackFieldValue], issue data: Data) throws -> [YouTrackFieldUpdate] {
		let fields = try JSONDecoder().decode(IssueFields.self, from: data).customFields ?? []
		return values.compactMap { picked in
			guard let field = fields.first(where: { $0.name == picked.field }) else {
				return .hidden(field: picked.field)
			}
			guard let fieldId = field.id, let type = field.type else {
				return .impossible(field: picked.field, reason: "YouTrack did not describe the field.")
			}
			guard Set(field.value?.names ?? []) != Set(picked.values) else {
				return nil
			}
			guard type == stateMachineIssueFieldType else {
				return .set(
					field: picked.field,
					fieldId: fieldId,
					issueFieldType: type,
					values: picked.values,
					isMultiValue: field.value?.isMultiple ?? type.hasPrefix("Multi")
				)
			}
			guard let target = picked.values.first,
			      let event = field.possibleEvents?.first(where: {
			      	$0.presentation?.caseInsensitiveCompare(target) == .orderedSame
			      }),
			      let eventId = event.id
			else {
				let current = field.value?.names.first ?? "empty"
				return .impossible(
					field: picked.field,
					reason: "its workflow does not go from \(current) to \(picked.values.first ?? "empty")."
				)
			}
			return .event(field: picked.field, fieldId: fieldId, eventId: eventId)
		}
	}

	/// Replaces the values of each field a state-machine workflow drives with its starting value
	/// followed by the events YouTrack offers from it, taken from the first sample ticket still at
	/// that value. Internal so the matching is unit-testable from fixture JSON.
	internal static func applyingWorkflowEvents(
		to fields: YouTrackProjectFields,
		sampleIssues data: Data
	) throws -> YouTrackProjectFields {
		let issues = try JSONDecoder().decode([IssueFields].self, from: data)
		let choiceFields = fields.choiceFields.map { field -> YouTrackChoiceField in
			guard !field.isMultiValue else {
				return field
			}
			let start = field.defaultValues.first
			let sample = issues.lazy
				.compactMap { $0.customFields?.first { $0.name == field.name } }
				.first { $0.type == stateMachineIssueFieldType && $0.value?.names.first == start }
			let events = sample?.possibleEvents?.compactMap(\.presentation).filter { !$0.isEmpty } ?? []
			guard !events.isEmpty else {
				return field
			}
			return YouTrackChoiceField(
				name: field.name,
				values: (start.map { [$0] } ?? []) + events.filter { $0 != start },
				defaultValues: field.defaultValues,
				isMultiValue: false,
				canBeEmpty: start == nil,
				eventDriven: true,
				condition: field.condition
			)
		}
		return YouTrackProjectFields(
			choiceFields: choiceFields,
			assignableLogins: fields.assignableLogins,
			initialValues: fields.initialValues,
			stateFieldName: fields.stateFieldName
		)
	}

	internal static func setFieldBody(type: String, values: [String], isMultiValue: Bool) throws -> Data {
		let value: Any = if isMultiValue {
			values.map { ["name": $0] }
		}
		else if let first = values.first {
			["name": first]
		}
		else {
			NSNull()
		}
		return try JSONSerialization.data(withJSONObject: ["$type": type, "value": value], options: .sortedKeys)
	}

	internal static func parseCreatedIssue(from data: Data) throws -> YouTrackIssueSummary {
		guard let issue = try? JSONDecoder().decode(CreatedIssue.self, from: data), !issue.idReadable.isEmpty else {
			throw YouTrackServiceError.unexpectedResponse
		}
		return YouTrackIssueSummary(id: issue.idReadable, summary: issue.summary ?? "")
	}

	internal static func parseProjects(from data: Data) throws -> [YouTrackProject] {
		try JSONDecoder().decode([ProjectHit].self, from: data)
			.compactMap { hit -> YouTrackProject? in
				guard hit.archived != true, let id = hit.id, let shortName = hit.shortName, !shortName.isEmpty else {
					return nil
				}
				return YouTrackProject(id: id, shortName: shortName, name: hit.name ?? shortName)
			}
			.sorted { $0.shortName.localizedStandardCompare($1.shortName) == .orderedAscending }
	}

	internal static func parseProjectFields(from data: Data) throws -> YouTrackProjectFields {
		let fields = try JSONDecoder().decode([ProjectFieldHit].self, from: data)
		let choiceFields = fields.compactMap { hit -> YouTrackChoiceField? in
			guard let name = hit.field?.name, let bundleType = hit.bundle?.type, choiceBundleTypes.contains(bundleType) else {
				return nil
			}
			let values = hit.bundle?.values?.filter { $0.archived != true }.compactMap(\.name) ?? []
			guard !values.isEmpty else {
				return nil
			}
			return YouTrackChoiceField(
				name: name,
				values: values,
				defaultValues: hit.defaultValues?.compactMap(\.name).filter(values.contains) ?? [],
				isMultiValue: hit.field?.fieldType?.isMultiValue ?? false,
				canBeEmpty: hit.canBeEmpty ?? true,
				condition: hit.condition.flatMap { condition in
					condition.field?.field?.name.map {
						YouTrackFieldCondition(field: $0, values: condition.values?.compactMap(\.name) ?? [])
					}
				}
			)
		}
		let assignee = fields.first { $0.type == "UserProjectCustomField" && $0.field?.name == assigneeFieldName }
		let initialValues = fields.compactMap { hit in
			hit.field?.name.map { ($0, hit.defaultValues?.compactMap(\.name) ?? []) }
		}
		return YouTrackProjectFields(
			choiceFields: choiceFields,
			assignableLogins: assignee.map { Set($0.bundle?.aggregatedUsers?.compactMap(\.login) ?? []) },
			initialValues: Dictionary(initialValues, uniquingKeysWith: { first, _ in first }),
			stateFieldName: fields.first { $0.type == "StateProjectCustomField" }?.field?.name
		)
	}

	private static let stateMachineIssueFieldType = "StateMachineIssueCustomField"

	static let hiddenFieldReason = "the ticket does not show it: YouTrack shows it only while another field has a certain value."

	private static func authorizedRequest(
		path: String,
		query: [URLQueryItem],
		baseURL: String,
		authToken: String
	) throws -> URLRequest {
		guard !authToken.isEmpty else {
			throw YouTrackServiceError.missingToken
		}
		let base = YouTrackURLBuilder.normalizedBase(baseURL)
		guard !base.isEmpty else {
			throw YouTrackServiceError.missingBaseURL
		}
		guard var components = URLComponents(string: "\(base)\(path)") else {
			throw YouTrackServiceError.invalidURL
		}
		components.queryItems = query
		guard let url = components.url else {
			throw YouTrackServiceError.invalidURL
		}
		var request = URLRequest(url: url)
		request.httpMethod = "GET"
		request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
		request.setValue("application/json", forHTTPHeaderField: "Accept")
		return request
	}

	private static func send(_ request: URLRequest) async throws -> Data {
		let (data, response) = try await URLSession.shared.loggedData(for: request)
		guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
			throw YouTrackServiceError.httpFailure(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1)
		}
		return data
	}
}

extension YouTrackFieldUpdate {
	var field: String {
		switch self {
		case let .event(field, _, _), let .set(field, _, _, _, _), let .hidden(field), let .impossible(field, _):
			field
		}
	}
}

private nonisolated struct CreatedIssue: Decodable {
	let idReadable: String
	let summary: String?
}

private nonisolated struct ProjectHit: Decodable {
	let id: String?
	let shortName: String?
	let name: String?
	let archived: Bool?
}

private nonisolated struct ProjectFieldHit: Decodable {
	struct FieldType: Decodable {
		let isMultiValue: Bool?
	}

	struct Field: Decodable {
		let name: String?
		let fieldType: FieldType?
	}

	struct Named: Decodable {
		let name: String?
	}

	struct Value: Decodable {
		let name: String?
		let archived: Bool?
	}

	struct User: Decodable {
		let login: String?
	}

	/// A `FieldBasedCondition`: `field` is the controlling project field, named by its own `field`.
	struct Condition: Decodable {
		struct ProjectField: Decodable {
			let field: Named?
		}

		let field: ProjectField?
		let values: [Named]?
	}

	struct Bundle: Decodable {
		let type: String?
		let values: [Value]?
		let aggregatedUsers: [User]?

		enum CodingKeys: String, CodingKey {
			case type = "$type"
			case values
			case aggregatedUsers
		}
	}

	let type: String?
	let canBeEmpty: Bool?
	let field: Field?
	let defaultValues: [Named]?
	let bundle: Bundle?
	let condition: Condition?

	enum CodingKeys: String, CodingKey {
		case type = "$type"
		case canBeEmpty
		case field
		case defaultValues
		case bundle
		case condition
	}
}

/// A filed ticket's fields, as `applyFieldValues` reads them.
private nonisolated struct IssueFields: Decodable {
	struct Event: Decodable {
		let id: String?
		let presentation: String?
	}

	/// A field's value: one named element, several, or null.
	enum Value: Decodable {
		case single(String?)
		case multiple([String])

		struct Named: Decodable {
			let name: String?
		}

		init(from decoder: any Decoder) throws {
			let container = try decoder.singleValueContainer()
			if let many = try? container.decode([Named].self) {
				self = .multiple(many.compactMap(\.name))
			}
			else {
				self = .single(try? container.decode(Named.self).name)
			}
		}

		var names: [String] {
			switch self {
			case let .single(name): name.map { [$0] } ?? []
			case let .multiple(names): names
			}
		}

		var isMultiple: Bool {
			if case .multiple = self { true } else { false }
		}
	}

	struct Field: Decodable {
		let type: String?
		let id: String?
		let name: String?
		let value: Value?
		let possibleEvents: [Event]?

		enum CodingKeys: String, CodingKey {
			case type = "$type"
			case id
			case name
			case value
			case possibleEvents
		}
	}

	let customFields: [Field]?
}
