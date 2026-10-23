import ComposableArchitecture
import Foundation
import GitCore
import Settings
import Testing
import ToolsIntegration
@testable import RepositoryFeature

// The create-worktree dialog's New Ticket tab: which project and fields it offers, what it files,
// and what happens when the worktree cannot follow the ticket.
@Suite("Create worktree dialog: new ticket source")
@MainActor
struct CreateWorktreeNewTicketTests {
	private let repo = "/nonexistent/repos/app"
	private let mob = YouTrackProject(id: "0-1", shortName: "MOB", name: "Mobile")
	private let app = YouTrackProject(id: "0-7", shortName: "APP", name: "App")
	private let mobFields = YouTrackProjectFields(
		choiceFields: [
			YouTrackChoiceField(name: "Type", values: ["Bug", "Task"], defaultValues: ["Task"], isMultiValue: false, canBeEmpty: false),
			YouTrackChoiceField(name: "Complexity", values: ["S", "M"], defaultValues: [], isMultiValue: false, canBeEmpty: true),
			YouTrackChoiceField(name: "Ready for dev", values: ["Design", "API"], defaultValues: [], isMultiValue: true, canBeEmpty: true),
		],
		assignableLogins: ["jane"]
	)

	@Test("switching to New Ticket lists projects and preselects the group's last one with its fields")
	func switchingLoadsProjects() async {
		let store = makeStore(rememberedProject: "0-1")

		await store.send(.sourceChanged(.newTicket)) {
			$0.source = .newTicket
		}
		await store.receive(\.newTicket.load) {
			$0.newTicket.isLoadingProjects = true
		}
		await store.receive(\.newTicket.loginLoaded) {
			$0.newTicket.login = "jane"
		}
		await store.receive(\.newTicket.projectsLoaded) {
			$0.newTicket.isLoadingProjects = false
			$0.newTicket.projects = [self.app, self.mob]
			$0.newTicket.selectedProjectId = "0-1"
			$0.newTicket.isLoadingFields = true
		}
		await store.receive(\.newTicket.fieldsLoaded) {
			$0.newTicket.isLoadingFields = false
			$0.newTicket.fields = self.mobFields
			$0.newTicket.fieldSelections = ["Type": ["Task"], "Complexity": [], "Ready for dev": []]
		}
	}

	@Test("picking a project remembers it for the group, and an answer for an earlier pick is dropped")
	func pickingRemembersProject() async {
		var state = makeState()
		state.source = .newTicket
		state.newTicket.projects = [app, mob]
		let store = TestStore(initialState: state) {
			CreateWorktreeButtonReducer()
		} withDependencies: {
			$0[YouTrackClient.self].projectFields = { _, _, _ in self.mobFields }
		}
		store.exhaustivity = .off

		await store.send(.newTicket(.projectSelected("0-1")))
		await store.receive(\.newTicket.fieldsLoaded)
		#expect(store.state.newTicket.groupSettings[repo]?.newTicketProjectId == "0-1")
		#expect(store.state.newTicket.fieldSelections["Type"] == ["Task"])

		await store.send(.newTicket(.fieldsLoaded(projectId: "0-7", YouTrackProjectFields(
			choiceFields: [YouTrackChoiceField(name: "Type", values: ["Epic"], defaultValues: ["Epic"], isMultiValue: false, canBeEmpty: false)],
			assignableLogins: nil
		))))
		#expect(store.state.newTicket.fields == mobFields)
	}

	@Test("Create waits for a project, its fields and a summary; the ticket is assigned only when the project takes the user")
	func formCompleteness() {
		var state = makeState()
		state.source = .newTicket
		state.availableBranches = [BranchInfo(name: "develop", existsLocally: true, existsRemotely: true)]
		state.newTicket.projects = [mob]
		state.newTicket.selectedProjectId = "0-1"
		state.newTicket.summary = "  "
		#expect(!state.canCreate)

		state.newTicket.summary = " Fix login "
		#expect(!state.canCreate)

		state.newTicket.fields = mobFields
		state.newTicket.$assignToMe.withLock { $0 = true }
		#expect(state.canCreate)
		// Who the token is is not known yet.
		#expect(state.newTicket.issue?.assigneeLogin == nil)

		state.newTicket.login = "jane"
		#expect(state.newTicket.issue == NewYouTrackIssue(
			projectId: "0-1",
			summary: "Fix login",
			description: "",
			assigneeLogin: "jane"
		))
		#expect(state.newTicket.branchPreview(template: BranchNameFormatter.defaultTicketBranchTemplate) == "fix_login_MOB-…")

		state.newTicket.login = "someone.else"
		#expect(state.newTicket.issue?.assigneeLogin == nil)
	}

	@Test("only picks that differ from the project's defaults are sent, in field order; multi-values keep the field's order")
	func fieldSelections() async {
		var state = makeState()
		state.source = .newTicket
		state.newTicket.projects = [mob]
		state.newTicket.selectedProjectId = "0-1"
		state.newTicket.summary = "Fix login"
		let store = TestStore(initialState: state) {
			CreateWorktreeButtonReducer()
		}
		store.exhaustivity = .off

		await store.send(.newTicket(.fieldsLoaded(projectId: "0-1", mobFields)))
		#expect(store.state.newTicket.issue?.fieldValues == [])

		await store.send(.newTicket(.fieldValueChanged(field: "Ready for dev", values: ["API", "Design"])))
		await store.send(.newTicket(.fieldValueChanged(field: "Complexity", values: ["M"])))
		await store.send(.newTicket(.fieldValueChanged(field: "Type", values: ["Task"])))
		await store.send(.newTicket(.fieldValueChanged(field: "Unknown", values: ["x"])))
		#expect(store.state.newTicket.issue?.fieldValues == [
			YouTrackFieldValue(field: "Complexity", values: ["M"]),
			YouTrackFieldValue(field: "Ready for dev", values: ["Design", "API"]),
		])

		await store.send(.newTicket(.fieldValueChanged(field: "Type", values: [])))
		#expect(store.state.newTicket.issue?.fieldValues.first == YouTrackFieldValue(field: "Type", values: []))
	}

	@Test("a conditional field is offered only while its condition holds; one shown from In Progress on is set after the move")
	func conditionalFields() {
		var state = makeState()
		state.source = .newTicket
		state.newTicket.projects = [mob]
		state.newTicket.selectedProjectId = "0-1"
		state.newTicket.summary = "Fix login"
		let inProgressStates = ["In Progress", "Done"]
		state.newTicket.fields = YouTrackProjectFields(
			choiceFields: [
				YouTrackChoiceField(name: "Team task", values: ["No", "Yes"], defaultValues: ["No"], isMultiValue: false, canBeEmpty: false),
				YouTrackChoiceField(
					name: "Ready for dev", values: ["Design"], defaultValues: [], isMultiValue: false, canBeEmpty: true,
					condition: YouTrackFieldCondition(field: "Team task", values: ["Yes"])
				),
				YouTrackChoiceField(
					name: "iOS CR", values: ["N/A", "Waiting"], defaultValues: ["N/A"], isMultiValue: false, canBeEmpty: false,
					eventDriven: true, condition: YouTrackFieldCondition(field: "State", values: inProgressStates)
				),
			],
			assignableLogins: nil,
			initialValues: ["State": ["Open"], "Team task": ["No"]],
			stateFieldName: "State"
		)
		state.newTicket.fieldSelections = ["Team task": ["No"], "Ready for dev": ["Design"], "iOS CR": ["Waiting"]]
		#expect(state.newTicket.shownChoiceFields.map(\.name) == ["Team task"])
		// Picks for hidden fields are not sent.
		#expect(state.newTicket.issue?.fieldValues == [])
		#expect(state.newTicket.fieldValuesOnceInProgress == [])

		state.newTicket.fieldSelections["Team task"] = ["Yes"]
		state.newTicket.$moveToInProgress.withLock { $0 = true }
		#expect(state.newTicket.shownChoiceFields.map(\.name) == ["Team task", "Ready for dev", "iOS CR"])
		#expect(state.newTicket.issue?.fieldValues == [
			YouTrackFieldValue(field: "Team task", values: ["Yes"]),
			YouTrackFieldValue(field: "Ready for dev", values: ["Design"]),
		])
		#expect(state.newTicket.fieldValuesOnceInProgress == [YouTrackFieldValue(field: "iOS CR", values: ["Waiting"])])
		#expect(state.newTicket.choiceFieldSections.map(\.title) == [nil, "When Team task is Yes", "Once In Progress"])
		#expect(state.newTicket.choiceFieldSections.map { $0.fields.map(\.name) } == [["Team task"], ["Ready for dev"], ["iOS CR"]])
	}

	@Test("field values YouTrack would not set become warnings prefixed with the ticket, and none are asked for when nothing was picked")
	func fieldValueWarnings() async {
		let asked = LockIsolated<[YouTrackFieldValue]>([])
		var client = YouTrackClient()
		client.applyFieldValues = { values, ticketId, _, _ in
			#expect(ticketId == "MOB-5001")
			asked.setValue(values)
			return ["iOS Review was not set: its workflow does not go from N/A to Passed."]
		}
		let values = [YouTrackFieldValue(field: "iOS Review", values: ["Passed"])]
		let warnings = await CreateWorktreeButtonReducer.applyFieldValues(
			values, ticketId: "MOB-5001", baseURL: "https://yt.example", authToken: "token", youTrackClient: client
		)
		#expect(asked.value == values)
		#expect(warnings == ["MOB-5001's iOS Review was not set: its workflow does not go from N/A to Passed."])

		client.applyFieldValues = { _, _, _, _ in throw YouTrackServiceError.httpFailure(statusCode: 500) }
		let failed = await CreateWorktreeButtonReducer.applyFieldValues(
			values, ticketId: "MOB-5001", baseURL: "https://yt.example", authToken: "token", youTrackClient: client
		)
		#expect(failed == ["MOB-5001's fields were not set: Could not read them: HTTP 500"])

		let none = await CreateWorktreeButtonReducer.applyFieldValues(
			[], ticketId: "MOB-5001", baseURL: "https://yt.example", authToken: "token", youTrackClient: YouTrackClient()
		)
		#expect(none.isEmpty)
	}

	@Test("a ticket YouTrack refuses says why, and no worktree is attempted")
	func refusedTicket() async {
		let store = TestStore(initialState: readyState()) {
			CreateWorktreeButtonReducer()
		} withDependencies: {
			$0[YouTrackClient.self].createIssue = { _, _, _ in
				throw YouTrackServiceError.httpFailure(statusCode: 403)
			}
		}
		store.exhaustivity = .off

		await store.send(.confirmCreation)
		await store.receive(\.didFailWithError)
		#expect(store.state.errorAlert?.message == TextState("The YouTrack token may not create tickets in MOB."))
	}

	@Test("a worktree that fails after the ticket was filed names the ticket to retry from")
	func worktreeFailsAfterTicket() async {
		let filed = LockIsolated<NewYouTrackIssue?>(nil)
		let store = TestStore(initialState: readyState()) {
			CreateWorktreeButtonReducer()
		} withDependencies: {
			$0[YouTrackClient.self].createIssue = { issue, baseURL, authToken in
				#expect(baseURL == "https://yt.example")
				#expect(authToken == "token")
				filed.setValue(issue)
				return YouTrackIssueSummary(id: "MOB-5001", summary: issue.summary)
			}
		}
		store.exhaustivity = .off

		await store.send(.confirmCreation)
		await store.receive(\.didFailWithError, timeout: .seconds(30))
		#expect(filed.value?.projectId == "0-1")
		let message = String(describing: store.state.errorAlert?.message)
		#expect(message.contains("Created MOB-5001, but the worktree failed"))
		#expect(message.contains("Pick MOB-5001 on the Ticket tab"))
	}

	@Test("moving to In Progress applies the transition YouTrack offers, and says so when there is none")
	func moveToInProgress() async {
		let applied = LockIsolated<[String]>([])
		var client = YouTrackClient()
		client.applyStateEvent = { ticketId, fieldId, eventId, _, _ in
			applied.withValue { $0.append("\(ticketId) \(fieldId) \(eventId)") }
		}
		client.fetchIssueDetails = { _, _, _ in
			IssueDetails(
				androidCR: nil, iosCR: nil, androidReviewerName: nil, iosReviewerName: nil,
				ticketState: .open,
				stateFieldId: "84-950",
				stateTransitions: [
					TicketStateTransition(eventId: "dup", presentation: "Duplicate"),
					TicketStateTransition(eventId: "start", presentation: "In Progress"),
				]
			)
		}
		let warning = await CreateWorktreeButtonReducer.moveToInProgress(
			ticketId: "MOB-5001", baseURL: "https://yt.example", authToken: "token", youTrackClient: client
		)
		#expect(warning == nil)
		#expect(applied.value == ["MOB-5001 84-950 start"])

		client.fetchIssueDetails = { _, _, _ in
			IssueDetails(androidCR: nil, iosCR: nil, androidReviewerName: nil, iosReviewerName: nil, ticketState: .open)
		}
		let missing = await CreateWorktreeButtonReducer.moveToInProgress(
			ticketId: "MOB-5001", baseURL: "https://yt.example", authToken: "token", youTrackClient: client
		)
		#expect(missing == "MOB-5001 was not moved to In Progress: YouTrack offers no such transition from its state.")
	}

	// MARK: - Helpers

	private func makeState(rememberedProject: String = "") -> CreateWorktreeButtonReducer.State {
		@Shared(.groupSettings) var groupSettings: [String: RepoGroupSettings] = [:]
		$groupSettings.withLock {
			$0[repo] = RepoGroupSettings(youtrackBaseURL: "https://yt.example", newTicketProjectId: rememberedProject)
		}
		@Shared(.youtrackAuthToken) var token = ""
		$token.withLock { $0 = "token" }
		@Shared(.newTicketAssignToMe) var assignToMe = false
		$assignToMe.withLock { $0 = false }
		@Shared(.newTicketMoveToInProgress) var moveToInProgress = false
		$moveToInProgress.withLock { $0 = false }
		return CreateWorktreeButtonReducer.State(repositoryPath: repo)
	}

	/// A New Ticket form ready to submit, in a repository that does not exist.
	private func readyState() -> CreateWorktreeButtonReducer.State {
		var state = makeState()
		state.source = .newTicket
		state.showCreateDialog = true
		state.availableBranches = [BranchInfo(name: "develop", existsLocally: true, existsRemotely: false)]
		state.selectedBaseBranch = "develop"
		state.newTicket.projects = [mob]
		state.newTicket.selectedProjectId = "0-1"
		state.newTicket.fields = mobFields
		state.newTicket.summary = "Fix login"
		return state
	}

	private func makeStore(rememberedProject: String) -> TestStoreOf<CreateWorktreeButtonReducer> {
		// Built before the store: `initialState` is evaluated inside the store's dependency scope,
		// where writing the shared settings would register as an unexpected state change.
		let state = makeState(rememberedProject: rememberedProject)
		return TestStore(initialState: state) {
			CreateWorktreeButtonReducer()
		} withDependencies: {
			$0[YouTrackClient.self].listProjects = { baseURL, authToken in
				#expect(baseURL == "https://yt.example")
				#expect(authToken == "token")
				return [self.app, self.mob]
			}
			$0[YouTrackClient.self].verifyToken = { _, _ in "jane" }
			$0[YouTrackClient.self].projectFields = { project, _, _ in
				#expect(project == self.mob)
				return self.mobFields
			}
		}
	}
}
