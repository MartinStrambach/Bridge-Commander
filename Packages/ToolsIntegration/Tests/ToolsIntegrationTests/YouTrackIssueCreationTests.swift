import Foundation
import Testing
@testable import ToolsIntegration

@Suite("YouTrack issue creation")
struct YouTrackIssueCreationTests {
	@Test("projects are listed by short name, archived ones and those without a short name left out")
	func parsesProjects() throws {
		let json = Data("""
		[
		  {"shortName": "MOB", "archived": false, "name": "Mobile", "id": "0-1", "$type": "Project"},
		  {"shortName": "OLD", "archived": true, "name": "Old", "id": "0-2", "$type": "Project"},
		  {"shortName": "APP", "name": "App", "id": "0-7", "$type": "Project"},
		  {"name": "Nameless", "id": "0-9", "$type": "Project"}
		]
		""".utf8)
		#expect(try YouTrackService.parseProjects(from: json) == [
			YouTrackProject(id: "0-7", shortName: "APP", name: "App"),
			YouTrackProject(id: "0-1", shortName: "MOB", name: "Mobile"),
		])
	}

	/// Shape captured from a real project's `customFields`, trimmed.
	@Test("choice fields come in the project's order with defaults and multi-value; State and user fields are left out")
	func parsesProjectFields() throws {
		let json = Data("""
		[
		  {
		    "$type": "EnumProjectCustomField",
		    "canBeEmpty": false,
		    "field": {"name": "Type", "fieldType": {"isMultiValue": false}},
		    "defaultValues": [{"name": "Task", "$type": "EnumBundleElement"}],
		    "bundle": {"values": [
		      {"name": "Bug", "archived": false},
		      {"name": "Legacy", "archived": true},
		      {"name": "Task", "archived": false}
		    ], "$type": "EnumBundle"}
		  },
		  {
		    "$type": "StateProjectCustomField",
		    "canBeEmpty": false,
		    "field": {"name": "State", "fieldType": {"isMultiValue": false}},
		    "defaultValues": [{"name": "Open"}],
		    "bundle": {"values": [{"name": "Open"}], "$type": "StateBundle"}
		  },
		  {
		    "$type": "EnumProjectCustomField",
		    "canBeEmpty": true,
		    "field": {"name": "Ready for dev", "fieldType": {"isMultiValue": true}},
		    "defaultValues": [{"name": "Gone"}],
		    "bundle": {"values": [{"name": "Design"}, {"name": "API"}], "$type": "EnumBundle"},
		    "condition": {"$type": "FieldBasedCondition", "field": {"field": {"name": "Type"}}, "values": [{"name": "Task"}]}
		  },
		  {
		    "$type": "EnumProjectCustomField",
		    "field": {"name": "Empty"},
		    "bundle": {"values": [], "$type": "EnumBundle"}
		  },
		  {
		    "$type": "VersionProjectCustomField",
		    "canBeEmpty": true,
		    "field": {"name": "Fix version"},
		    "bundle": {"values": [{"name": "1.0"}], "$type": "VersionBundle"}
		  },
		  {
		    "$type": "UserProjectCustomField",
		    "field": {"name": "Assignee", "$type": "CustomField"},
		    "defaultValues": [],
		    "bundle": {"aggregatedUsers": [{"login": "jane"}, {"login": "jan"}], "$type": "UserBundle"}
		  },
		  {
		    "$type": "UserProjectCustomField",
		    "field": {"name": "Taker", "$type": "CustomField"},
		    "bundle": {"aggregatedUsers": [{"login": "someone"}], "$type": "UserBundle"}
		  }
		]
		""".utf8)
		let fields = try YouTrackService.parseProjectFields(from: json)
		#expect(fields.choiceFields == [
			YouTrackChoiceField(name: "Type", values: ["Bug", "Task"], defaultValues: ["Task"], isMultiValue: false, canBeEmpty: false),
			// A default that is not among the values is dropped.
			YouTrackChoiceField(
				name: "Ready for dev", values: ["Design", "API"], defaultValues: [], isMultiValue: true, canBeEmpty: true,
				condition: YouTrackFieldCondition(field: "Type", values: ["Task"])
			),
			YouTrackChoiceField(name: "Fix version", values: ["1.0"], defaultValues: [], isMultiValue: false, canBeEmpty: true),
		])
		#expect(fields.canAssign("jane"))
		#expect(!fields.canAssign("someone"))
		#expect(fields.stateFieldName == "State")
		#expect(fields.initialValues["State"] == ["Open"])
		#expect(fields.initialValues["Type"] == ["Task"])
	}

	@Test("a conditional field is shown only while its controlling field, picked or at its default, holds one of its values")
	func conditionalFieldsShow() {
		let review = YouTrackChoiceField(
			name: "iOS CR", values: ["N/A"], defaultValues: ["N/A"], isMultiValue: false, canBeEmpty: false,
			condition: YouTrackFieldCondition(field: "State", values: ["In Progress", "Done"])
		)
		let never = YouTrackChoiceField(
			name: "Utilization", values: ["x"], defaultValues: [], isMultiValue: false, canBeEmpty: true,
			condition: YouTrackFieldCondition(field: "State", values: [])
		)
		let always = YouTrackChoiceField(name: "Priority", values: ["Normal"], defaultValues: [], isMultiValue: false, canBeEmpty: true)
		let fields = YouTrackProjectFields(
			choiceFields: [review, never, always],
			assignableLogins: nil,
			initialValues: ["State": ["Open"]],
			stateFieldName: "State"
		)
		#expect(!fields.shows(review, values: [:]))
		#expect(fields.shows(review, values: ["State": ["In Progress"]]))
		#expect(!fields.shows(never, values: ["State": ["In Progress"]]))
		#expect(fields.shows(always, values: [:]))
	}

	/// Shape of recent tickets from `GET /api/issues?fields=customFields($type,name,value(name),possibleEvents(…))`.
	@Test("a workflow-driven field offers the events from a new ticket's starting value, read from a ticket still at it")
	func workflowFieldsOfferEvents() throws {
		let fields = YouTrackProjectFields(
			choiceFields: [
				YouTrackChoiceField(name: "iOS Review", values: ["N/A", "Waiting", "Passed"], defaultValues: ["N/A"], isMultiValue: false, canBeEmpty: false),
				YouTrackChoiceField(name: "Review", values: ["Done"], defaultValues: [], isMultiValue: false, canBeEmpty: true),
				YouTrackChoiceField(name: "Priority", values: ["Normal", "Major"], defaultValues: ["Normal"], isMultiValue: false, canBeEmpty: false),
				YouTrackChoiceField(name: "Android Review", values: ["N/A", "Waiting"], defaultValues: ["N/A"], isMultiValue: false, canBeEmpty: false),
			],
			assignableLogins: nil
		)
		let samples = Data("""
		[
		  {"customFields": [
		    {"$type": "StateMachineIssueCustomField", "name": "iOS Review", "value": {"name": "Passed"},
		     "possibleEvents": [{"id": "fail", "presentation": "fail"}]},
		    {"$type": "StateMachineIssueCustomField", "name": "Android Review", "value": {"name": "Waiting"},
		     "possibleEvents": [{"id": "take", "presentation": "take"}]}
		  ]},
		  {"customFields": [
		    {"$type": "StateMachineIssueCustomField", "name": "iOS Review", "value": {"name": "N/A"},
		     "possibleEvents": [{"id": "needed", "presentation": "needed"}, {"id": "nn", "presentation": "not needed"}]},
		    {"$type": "StateMachineIssueCustomField", "name": "Review", "value": null,
		     "possibleEvents": [{"id": "ask", "presentation": "ask"}]},
		    {"$type": "SingleEnumIssueCustomField", "name": "Priority", "value": {"name": "Normal"}}
		  ]},
		  {"customFields": []}
		]
		""".utf8)
		let result = try YouTrackService.applyingWorkflowEvents(to: fields, sampleIssues: samples)
		#expect(result.choiceFields == [
			YouTrackChoiceField(
				name: "iOS Review", values: ["N/A", "needed", "not needed"], defaultValues: ["N/A"],
				isMultiValue: false, canBeEmpty: false, eventDriven: true
			),
			YouTrackChoiceField(name: "Review", values: ["ask"], defaultValues: [], isMultiValue: false, canBeEmpty: true, eventDriven: true),
			fields.choiceFields[2],
			// No sample is at N/A: its values stay.
			fields.choiceFields[3],
		])
	}

	@Test("a project without an Assignee field takes no assignee")
	func projectWithoutAssignee() throws {
		let json = Data("""
		[{"$type": "EnumProjectCustomField", "field": {"name": "Kind"}, "bundle": {"values": [{"name": "Bug"}], "$type": "EnumBundle"}}]
		""".utf8)
		let fields = try YouTrackService.parseProjectFields(from: json)
		#expect(fields.assignableLogins == nil)
		#expect(fields.choiceFields.map(\.name) == ["Kind"])
		#expect(!fields.canAssign("jane"))
	}

	@Test("a new ticket is sent with its project id, and with an Assignee only when picked")
	func createBody() throws {
		let bare = try YouTrackService.createIssueBody(
			NewYouTrackIssue(projectId: "0-1", summary: "Fix login", description: "", assigneeLogin: nil)
		)
		#expect(String(decoding: bare, as: UTF8.self)
			== #"{"description":"","project":{"id":"0-1"},"summary":"Fix login"}"#)

		let full = try YouTrackService.createIssueBody(NewYouTrackIssue(
			projectId: "0-1",
			summary: "Fix login",
			description: "Steps",
			assigneeLogin: "me",
			fieldValues: [YouTrackFieldValue(field: "Priority", values: ["Major"])]
		))
		let object = try #require(JSONSerialization.jsonObject(with: full) as? [String: Any])
		let customFields = try #require(object["customFields"] as? [[String: Any]])
		#expect(customFields.count == 1)
		#expect(customFields[0]["name"] as? String == "Assignee")
		#expect(customFields[0]["$type"] as? String == "SingleUserIssueCustomField")
		#expect((customFields[0]["value"] as? [String: String]) == ["login": "me"])
	}

	/// Shape of `GET /api/issues/{id}?fields=customFields($type,id,name,value(name),possibleEvents(id,presentation))`.
	@Test("picked values become direct writes, or events for state-machine fields; unchanged ones are skipped")
	func plansFieldUpdates() throws {
		let issue = Data("""
		{"customFields": [
		  {"$type": "SingleEnumIssueCustomField", "id": "1", "name": "Priority", "value": {"name": "Normal"}},
		  {"$type": "SingleEnumIssueCustomField", "id": "2", "name": "Complexity", "value": null},
		  {"$type": "MultiEnumIssueCustomField", "id": "3", "name": "Ready for dev", "value": []},
		  {"$type": "StateMachineIssueCustomField", "id": "4", "name": "iOS Review", "value": {"name": "N/A"},
		   "possibleEvents": [{"id": "needed", "presentation": "Needed"}, {"id": "nn", "presentation": "Not needed"}]},
		  {"$type": "StateMachineIssueCustomField", "id": "5", "name": "Android Review", "value": {"name": "N/A"},
		   "possibleEvents": [{"id": "needed", "presentation": "Needed"}]},
		  {"$type": "SingleEnumIssueCustomField", "id": "6", "name": "Detected in", "value": {"name": "Prod"}}
		]}
		""".utf8)
		let updates = try YouTrackService.fieldUpdates(for: [
			YouTrackFieldValue(field: "Priority", values: ["Major"]),
			YouTrackFieldValue(field: "Complexity", values: []),
			YouTrackFieldValue(field: "Ready for dev", values: ["Design", "API"]),
			YouTrackFieldValue(field: "iOS Review", values: ["needed"]),
			YouTrackFieldValue(field: "Android Review", values: ["Passed"]),
			YouTrackFieldValue(field: "Detected in", values: []),
			YouTrackFieldValue(field: "Gone", values: ["x"]),
		], issue: issue)
		#expect(updates == [
			.set(field: "Priority", fieldId: "1", issueFieldType: "SingleEnumIssueCustomField", values: ["Major"], isMultiValue: false),
			.set(field: "Ready for dev", fieldId: "3", issueFieldType: "MultiEnumIssueCustomField", values: ["Design", "API"], isMultiValue: true),
			.event(field: "iOS Review", fieldId: "4", eventId: "needed"),
			.impossible(field: "Android Review", reason: "its workflow does not go from N/A to Passed."),
			.set(field: "Detected in", fieldId: "6", issueFieldType: "SingleEnumIssueCustomField", values: [], isMultiValue: false),
			.hidden(field: "Gone"),
		])
	}

	@Test("a field write names the issue's field type, with one value, a list or null")
	func setFieldBodies() throws {
		func body(_ values: [String], multi: Bool) throws -> String {
			try String(decoding: YouTrackService.setFieldBody(type: "T", values: values, isMultiValue: multi), as: UTF8.self)
		}
		#expect(try body(["Major"], multi: false) == #"{"$type":"T","value":{"name":"Major"}}"#)
		#expect(try body([], multi: false) == #"{"$type":"T","value":null}"#)
		#expect(try body(["A", "B"], multi: true) == #"{"$type":"T","value":[{"name":"A"},{"name":"B"}]}"#)
	}

	@Test("the created ticket's readable id is what comes back; anything else is unexpected")
	func parsesCreatedIssue() throws {
		let json = Data(#"{"idReadable": "MOB-5001", "summary": "Fix login", "id": "2-99", "$type": "Issue"}"#.utf8)
		#expect(try YouTrackService.parseCreatedIssue(from: json) == YouTrackIssueSummary(id: "MOB-5001", summary: "Fix login"))
		#expect(throws: YouTrackServiceError.self) {
			try YouTrackService.parseCreatedIssue(from: Data("<html></html>".utf8))
		}
	}
}
