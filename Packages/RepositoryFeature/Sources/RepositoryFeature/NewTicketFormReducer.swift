import ComposableArchitecture
import Foundation
import GitCore
import Settings
import ToolsIntegration

/// A group of the New Ticket tab's choice fields: those always shown (no title), or the
/// conditional ones shown under one condition.
struct ChoiceFieldSection: Equatable, Identifiable {
	/// What shows the section's fields, or nil for the fields YouTrack always shows.
	let title: String?
	let fields: [YouTrackChoiceField]

	var id: String { title ?? "" }
}

/// The create-worktree dialog's New Ticket tab: the ticket to file before the worktree is made.
/// Filing it is the parent's job, done on Create together with the worktree.
@Reducer
struct NewTicketFormReducer {
	@ObservableState
	struct State: Equatable {
		let repositoryPath: String
		@Shared(.groupSettings)
		var groupSettings: [String: RepoGroupSettings] = [:]
		@Shared(.newTicketAssignToMe)
		var assignToMe = false
		@Shared(.newTicketMoveToInProgress)
		var moveToInProgress = false

		var projects: [YouTrackProject] = []
		var isLoadingProjects = false
		var projectsError: String?
		var selectedProjectId: String?

		/// The selected project's choice fields and Assignee setup; nil while it loads or after it
		/// failed.
		var fields: YouTrackProjectFields?
		var isLoadingFields = false
		var fieldsError: String?
		/// The values picked per choice field, by field name; seeded with each field's defaults.
		/// An empty list leaves the field without a value.
		var fieldSelections: [String: [String]] = [:]

		/// The token's user, for "Assign to me". Nil until known, or when the token could not say.
		var login: String?

		var summary = ""
		var description = ""

		init(repositoryPath: String) {
			self.repositoryPath = repositoryPath
		}

		var youtrackBaseURL: String {
			YouTrackURLBuilder.normalizedBase(groupSettings[repositoryPath]?.youtrackBaseURL ?? "")
		}

		var selectedProject: YouTrackProject? {
			selectedProjectId.flatMap { id in projects.first { $0.id == id } }
		}

		/// Whether the project's Assignee field takes the token's user.
		var canAssignToMe: Bool {
			guard let login, let fields else {
				return false
			}
			return fields.canAssign(login)
		}

		var trimmedSummary: String {
			summary.trimmingCharacters(in: .whitespacesAndNewlines)
		}

		/// Waits for the project's fields, so a value or assignee the user is about to pick is not
		/// silently left out.
		var canSubmit: Bool {
			selectedProject != nil && !trimmedSummary.isEmpty && fields != nil
		}

		/// What is filed on Create, or nil while the form is incomplete.
		var issue: NewYouTrackIssue? {
			guard canSubmit, let project = selectedProject else {
				return nil
			}
			return NewYouTrackIssue(
				projectId: project.id,
				summary: trimmedSummary,
				description: description.trimmingCharacters(in: .whitespacesAndNewlines),
				assigneeLogin: assignToMe && canAssignToMe ? login : nil,
				fieldValues: changedFieldValues
			)
		}

		func selection(of field: YouTrackChoiceField) -> [String] {
			fieldSelections[field.name] ?? field.defaultValues
		}

		/// The choice fields the ticket will show once filed (and moved to In Progress, when it is
		/// to be): a conditional field only while its condition holds for the current picks.
		var shownChoiceFields: [YouTrackChoiceField] {
			choiceFields(shownInProgress: moveToInProgress)
		}

		/// ``shownChoiceFields`` grouped for the form: the unconditional ones first, then one section
		/// per condition, in the order the project lists their first field.
		var choiceFieldSections: [ChoiceFieldSection] {
			let shown = shownChoiceFields
			var sections = [ChoiceFieldSection(title: nil, fields: shown.filter { $0.condition == nil })]
			var conditions: [YouTrackFieldCondition] = []
			for condition in shown.compactMap(\.condition) where !conditions.contains(condition) {
				conditions.append(condition)
			}
			sections += conditions.map { condition in
				ChoiceFieldSection(title: sectionTitle(for: condition), fields: shown.filter { $0.condition == condition })
			}
			return sections.filter { !$0.fields.isEmpty }
		}

		/// A State condition is shown only through the In Progress move; any other names its field
		/// and the values that show the section.
		private func sectionTitle(for condition: YouTrackFieldCondition) -> String {
			if condition.field == fields?.stateFieldName {
				return "Once In Progress"
			}
			let values = condition.values.count > 1
				? condition.values.dropLast().joined(separator: ", ") + " or " + condition.values[condition.values.count - 1]
				: condition.values.first ?? ""
			return "When \(condition.field) is \(values)"
		}

		/// Picks for fields the ticket shows only once it is In Progress (per-platform review
		/// fields), set after the transition. Empty unless the ticket is to be moved.
		var fieldValuesOnceInProgress: [YouTrackFieldValue] {
			guard moveToInProgress else {
				return []
			}
			let shownWhenFiled = Set(choiceFields(shownInProgress: false).map(\.name))
			return changedFieldValues(of: choiceFields(shownInProgress: true).filter { !shownWhenFiled.contains($0.name) })
		}

		/// The picks that differ from what YouTrack fills in by itself, for fields the ticket shows
		/// when filed, in the project's field order.
		private var changedFieldValues: [YouTrackFieldValue] {
			changedFieldValues(of: choiceFields(shownInProgress: false))
		}

		private func changedFieldValues(of fields: [YouTrackChoiceField]) -> [YouTrackFieldValue] {
			fields.compactMap { field in
				let picked = selection(of: field)
				return Set(picked) == Set(field.defaultValues) ? nil : YouTrackFieldValue(field: field.name, values: picked)
			}
		}

		/// The choice fields shown with the current picks, and the State either as a new ticket
		/// starts or In Progress.
		private func choiceFields(shownInProgress inProgress: Bool) -> [YouTrackChoiceField] {
			guard let fields else {
				return []
			}
			var values = Dictionary(fields.choiceFields.map { ($0.name, selection(of: $0)) }, uniquingKeysWith: { first, _ in first })
			if inProgress, let stateField = fields.stateFieldName {
				values[stateField] = [TicketState.inProgress.rawValue]
			}
			return fields.choiceFields.filter { fields.shows($0, values: values) }
		}

		/// The branch the ticket will get, with its number shown as "…": YouTrack numbers it only
		/// when it is filed. Nil until there is a project and a summary.
		func branchPreview(template: String) -> String? {
			guard let project = selectedProject, !trimmedSummary.isEmpty else {
				return nil
			}
			return GitBranchNameSanitizer.sanitize(
				BranchNameFormatter.branchName(ticketId: "\(project.shortName)-…", summary: trimmedSummary, template: template)
			)
		}
	}

	enum Action: BindableAction {
		case binding(BindingAction<State>)
		/// Lists the projects and asks who the token is, unless already done or under way.
		case load
		case projectsLoaded([YouTrackProject])
		case projectsFailed(String)
		case loginLoaded(String?)
		case projectSelected(String?)
		case fieldsLoaded(projectId: String, YouTrackProjectFields)
		case fieldsFailed(projectId: String, String)
		/// Picks a choice field's values; empty clears it.
		case fieldValueChanged(field: String, values: [String])
		case assignToMeChanged(Bool)
		case moveToInProgressChanged(Bool)
	}

	private enum CancelID {
		case fields
	}

	@Dependency(YouTrackClient.self)
	private var youTrackClient

	var body: some Reducer<State, Action> {
		BindingReducer()
		Reduce { state, action in
			switch action {
			case .binding:
				return .none

			case .load:
				let baseURL = state.youtrackBaseURL
				guard !baseURL.isEmpty, !state.isLoadingProjects, state.projects.isEmpty else {
					return .none
				}
				state.isLoadingProjects = true
				state.projectsError = nil
				let authToken = Self.authToken
				return .run { [youTrackClient] send in
					async let login = try? youTrackClient.verifyToken(baseURL: baseURL, authToken: authToken)
					async let projects = Result {
						try await youTrackClient.listProjects(baseURL: baseURL, authToken: authToken)
					}
					// The login first: the projects' answer starts loading a project's fields,
					// which would otherwise race it.
					await send(.loginLoaded(await login))
					switch await projects {
					case let .success(projects):
						await send(.projectsLoaded(projects))
					case let .failure(error):
						await send(.projectsFailed(Self.errorMessage(for: error, doing: "list projects")))
					}
				}

			case let .projectsLoaded(projects):
				state.isLoadingProjects = false
				state.projects = projects
				let remembered = state.groupSettings[state.repositoryPath]?.newTicketProjectId ?? ""
				guard let project = projects.first(where: { $0.id == remembered }) else {
					return .none
				}
				return selectProject(project.id, in: &state)

			case let .projectsFailed(message):
				state.isLoadingProjects = false
				state.projectsError = message
				state.projects = []
				return .none

			case let .loginLoaded(login):
				state.login = login
				return .none

			case let .projectSelected(projectId):
				guard projectId != state.selectedProjectId else {
					return .none
				}
				if let projectId {
					state.$groupSettings.withLock {
						$0[state.repositoryPath, default: RepoGroupSettings()].newTicketProjectId = projectId
					}
				}
				return selectProject(projectId, in: &state)

			case let .fieldsLoaded(projectId, fields):
				// An answer for a project picked earlier must not land on the current one.
				guard projectId == state.selectedProjectId else {
					return .none
				}
				state.isLoadingFields = false
				state.fields = fields
				state.fieldSelections = Dictionary(
					fields.choiceFields.map { ($0.name, $0.defaultValues) },
					uniquingKeysWith: { first, _ in first }
				)
				return .none

			case let .fieldsFailed(projectId, message):
				guard projectId == state.selectedProjectId else {
					return .none
				}
				state.isLoadingFields = false
				state.fieldsError = message
				return .none

			case let .fieldValueChanged(field, values):
				guard let choice = state.fields?.choiceFields.first(where: { $0.name == field }) else {
					return .none
				}
				// Kept in the field's order, whatever order a multi-select was ticked in.
				state.fieldSelections[field] = choice.values.filter(values.contains)
				return .none

			case let .assignToMeChanged(assign):
				state.$assignToMe.withLock { $0 = assign }
				return .none

			case let .moveToInProgressChanged(move):
				state.$moveToInProgress.withLock { $0 = move }
				return .none
			}
		}
	}

	private func selectProject(_ projectId: String?, in state: inout State) -> Effect<Action> {
		state.selectedProjectId = projectId
		state.fields = nil
		state.fieldsError = nil
		state.fieldSelections = [:]
		guard let projectId, let project = state.projects.first(where: { $0.id == projectId }) else {
			state.isLoadingFields = false
			return .cancel(id: CancelID.fields)
		}
		state.isLoadingFields = true
		let baseURL = state.youtrackBaseURL
		let authToken = Self.authToken
		return .run { [youTrackClient] send in
			do {
				let fields = try await youTrackClient.projectFields(project: project, baseURL: baseURL, authToken: authToken)
				await send(.fieldsLoaded(projectId: projectId, fields))
			}
			catch {
				await send(.fieldsFailed(projectId: projectId, Self.errorMessage(for: error, doing: "read the project's fields")))
			}
		}
		.cancellable(id: CancelID.fields, cancelInFlight: true)
	}

	private static var authToken: String {
		@Shared(.youtrackAuthToken)
		var authToken = ""
		return authToken.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	static func errorMessage(for error: Error, doing task: String) -> String {
		switch error {
		case YouTrackServiceError.missingToken:
			"Add a YouTrack token in Settings to file tickets."
		case YouTrackServiceError.httpFailure(statusCode: 401):
			"YouTrack rejected the token — check it in Settings."
		case YouTrackServiceError.httpFailure(statusCode: 403):
			"The YouTrack token may not \(task)."
		case let YouTrackServiceError.httpFailure(statusCode):
			"Could not \(task): HTTP \(statusCode)"
		default:
			"Could not \(task): \(error.localizedDescription)"
		}
	}
}
