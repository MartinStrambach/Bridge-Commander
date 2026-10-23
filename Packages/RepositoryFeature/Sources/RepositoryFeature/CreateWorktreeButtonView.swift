import ComposableArchitecture
import SwiftUI
import AppUI
import GitCore
import GitHosting
import Settings
import ToolsIntegration

// MARK: - Dialog View

struct CreateWorktreeDialogView: View {
	@Bindable
	var store: StoreOf<CreateWorktreeButtonReducer>

	var body: some View {
		VStack(spacing: 20) {
			Text("Create New Worktree in \(store.repositoryName)")
				.scaledFont(.headline)
				.multilineTextAlignment(.center)

			Picker("Source", selection: $store.source.sending(\.sourceChanged)) {
				ForEach(store.availableSources, id: \.self) { source in
					Text(source.title).tag(source)
				}
			}
			.pickerStyle(.segmented)
			.labelsHidden()

			VStack(alignment: .leading, spacing: 12) {
				switch store.source {
				case .branch:
					branchSourceContent
				case .ticket:
					ticketSourceContent
				case .newTicket:
					NewTicketSourceView(
						store: store.scope(\.newTicket, action: \.newTicket),
						branchTemplate: store.ticketBranchNameTemplate
					)
					baseBranchPicker
					HStack {
						Spacer()
						startPointPicker
					}
				case .pullRequest:
					pullRequestSourceContent
				}

				Divider()
					.padding(.vertical, 4)

				followUpContent
			}

			HStack {
				Button("Cancel") {
					store.send(.cancelCreation)
				}
				.buttonStyle(.scaledAutomatic)
				.keyboardShortcut(.cancelAction)

				Spacer()

				Button("Create") {
					store.send(.confirmCreation)
				}
				.buttonStyle(.scaledAutomatic)
				.keyboardShortcut(.defaultAction)
				.disabled(!store.canCreate)
			}
		}
		.padding(24)
		// Grows with the "Start from" menu, which names the selected base branch in full.
		.frame(minWidth: 520, maxWidth: 800)
	}

	// MARK: - Branch

	@ViewBuilder
	private var branchSourceContent: some View {
		baseBranchPicker

		HStack {
			Toggle("Create new branch", isOn: $store.createNewBranch)
			Spacer()
			if store.showsStartPoint {
				startPointPicker
			}
		}

		if store.createNewBranch {
			newBranchNameField
		}
	}

	@ViewBuilder
	private var baseBranchPicker: some View {
		Text("Base Branch")
			.scaledFont(.subheadline)
			.foregroundColor(.secondary)

		if store.isLoadingBranches {
			ProgressView()
				.scaleEffect(0.7)
				.frame(maxWidth: .infinity)
		}
		else {
			TextField("Filter branches...", text: $store.branchSearchText)
				.textFieldStyle(.roundedBorder)

			Picker("Branch name", selection: $store.selectedBaseBranch) {
				ForEach(store.filteredBranches, id: \.self) { branchInfo in
					Text(branchInfo.name + (branchInfo.isRemoteOnly ? " (remote)" : ""))
						.foregroundColor(branchInfo.isRemoteOnly ? .orange.opacity(0.5) : .green.opacity(0.8))
						.tag(branchInfo.name)
				}
			}
			.pickerStyle(.menu)
			// A menu wants the width of its longest item, here any branch in the repository;
			// the dialog sizes to the selected one, through the "Start from" menu, instead.
			.frame(idealWidth: 200, maxWidth: .infinity)
			.disabled(store.filteredBranches.isEmpty)

		}
	}

	/// Where a new branch starts: the base as `origin` has it (just fetched), or the local branch.
	/// Disabled, showing the side that will be used, when the base exists on only one.
	/// At its natural width when the dialog has room, truncated otherwise: a fixed size wider than
	/// the dialog pushed the whole content past both of its edges.
	private var startPointPicker: some View {
		ViewThatFits(in: .horizontal) {
			startPointMenu.fixedSize()
			startPointMenu
		}
	}

	private var startPointMenu: some View {
		Picker("Start from", selection: Binding(
			get: { !store.startsFromOrigin },
			set: { store.send(.startFromLocalBaseChanged($0)) }
		)) {
			Text("origin/\(store.selectedBaseBranch)").tag(false)
			Text("Local \(store.selectedBaseBranch)").tag(true)
		}
		.pickerStyle(.menu)
		.disabled(!store.canChooseStartPoint)
	}

	@ViewBuilder
	private var newBranchNameField: some View {
		Text("New Branch Name")
			.scaledFont(.subheadline)
			.foregroundColor(.secondary)

		TextField("Enter branch name", text: $store.branchName)
			.textFieldStyle(.roundedBorder)
	}

	// MARK: - Ticket

	@ViewBuilder
	private var ticketSourceContent: some View {
		HStack {
			TextField("Search YouTrack — empty lists your open tickets", text: $store.ticketQuery)
				.textFieldStyle(.roundedBorder)
				.onSubmit { store.send(.searchTickets) }
			ProgressView()
				.scaleEffect(0.5)
				.frame(width: 16, height: 16)
				.opacity(store.isSearchingTickets ? 1 : 0)
		}

		List(selection: Binding(
			get: { store.selectedTicketId },
			set: { store.send(.ticketSelected($0)) }
		)) {
			ForEach(store.tickets) { ticket in
				TicketRow(ticket: ticket)
					.tag(ticket.id)
			}
		}
		.frame(height: 200)
		.overlay {
			if let error = store.ticketSearchError {
				listPlaceholder(error, isError: true)
			}
			else if store.tickets.isEmpty, !store.isSearchingTickets {
				listPlaceholder("No matching tickets")
			}
		}

		baseBranchPicker

		HStack {
			Spacer()
			startPointPicker
		}

		if store.selectedTicketId != nil {
			newBranchNameField
		}
	}

	// MARK: - Pull request

	@ViewBuilder
	private var pullRequestSourceContent: some View {
		HStack {
			TextField("Filter by title, branch, number or author", text: $store.pullRequestFilter)
				.textFieldStyle(.roundedBorder)
			if store.isLoadingPullRequests {
				ProgressView()
					.scaleEffect(0.5)
					.frame(width: 16, height: 16)
			}
			else {
				Button {
					store.send(.loadPullRequests)
				} label: {
					Image(systemName: "arrow.clockwise")
				}
				.buttonStyle(.borderless)
				.help("Reload open PRs/MRs")
			}
		}

		Toggle("Only mine", isOn: $store.onlyMyPullRequests.sending(\.onlyMyPullRequestsChanged))

		List(selection: Binding(
			get: { store.selectedPullRequestNumber },
			set: { store.send(.pullRequestSelected($0)) }
		)) {
			ForEach(store.filteredPullRequests) { pullRequest in
				PullRequestRow(pullRequest: pullRequest)
					.tag(pullRequest.number)
			}
		}
		.frame(height: 240)
		.overlay {
			if let error = store.pullRequestError {
				listPlaceholder(error, isError: true)
			}
			else if store.filteredPullRequests.isEmpty, !store.isLoadingPullRequests {
				listPlaceholder(pullRequestPlaceholder)
			}
		}

		if let pullRequest = store.selectedPullRequest {
			Text("Checks out \(pullRequest.headBranchLabel)\(pullRequest.isFromFork ? " from a fork" : "")")
				.scaledFont(.caption)
				.foregroundColor(.secondary)
				.lineLimit(1)
				.truncationMode(.middle)
		}
	}

	private var pullRequestPlaceholder: String {
		if store.pullRequests.isEmpty {
			"No open PRs/MRs"
		}
		else if store.onlyMyPullRequests, store.pullRequestFilter.trimmingCharacters(in: .whitespaces).isEmpty {
			"You have no open PRs/MRs here"
		}
		else {
			"No matching PRs/MRs"
		}
	}

	// MARK: - Follow-up

	@ViewBuilder
	private var followUpContent: some View {
		HStack {
			Text("After creating")
				.scaledFont(.subheadline)
				.foregroundColor(.secondary)
			Spacer()
			Picker("After creating", selection: $store.followUp.sending(\.followUpChanged)) {
				ForEach(WorktreeCreationFollowUp.allCases, id: \.self) { followUp in
					Text(followUp.title).tag(followUp)
				}
			}
			.pickerStyle(.segmented)
			.labelsHidden()
			.fixedSize()
		}

		if store.followUp == .runClaude {
			TextField(
				store.source == .newTicket ? "Prompt for Claude (blank: work on the new ticket)" : "Prompt for Claude (optional)",
				text: $store.claudePrompt,
				axis: .vertical
			)
			.textFieldStyle(.roundedBorder)
			.lineLimit(2 ... 4)
		}
	}

	private func listPlaceholder(_ text: String, isError: Bool = false) -> some View {
		Text(text)
			.scaledFont(.callout)
			.foregroundColor(isError ? .orange : .secondary)
			.multilineTextAlignment(.center)
			.padding()
	}
}

/// The New Ticket tab's ticket fields; the base branch below them is the dialog's own.
private struct NewTicketSourceView: View {
	@Bindable
	var store: StoreOf<NewTicketFormReducer>
	let branchTemplate: String

	var body: some View {
		HStack {
			Picker("Project", selection: $store.selectedProjectId.sending(\.projectSelected)) {
				Text("Choose a project").tag(String?.none)
				ForEach(store.projects) { project in
					Text("\(project.shortName) — \(project.name)").tag(String?.some(project.id))
				}
			}
			.disabled(store.projects.isEmpty)
			ProgressView()
				.scaleEffect(0.5)
				.frame(width: 16, height: 16)
				.opacity(store.isLoadingProjects || store.isLoadingFields ? 1 : 0)
		}

		if let error = store.projectsError ?? store.fieldsError {
			Text(error)
				.scaledFont(.caption)
				.foregroundColor(.orange)
		}

		TextField("Summary", text: $store.summary)
			.textFieldStyle(.roundedBorder)

		TextField("Description (optional)", text: $store.description, axis: .vertical)
			.textFieldStyle(.roundedBorder)
			.lineLimit(3 ... 6)

		ForEach(store.choiceFieldSections) { section in
			if let title = section.title {
				ChoiceFieldSectionHeader(title: title)
			}
			ChoiceFieldsGrid(fields: section.fields, store: store)
		}

		HStack {
			Toggle("Assign to me", isOn: $store.assignToMe.sending(\.assignToMeChanged))
				.disabled(!store.canAssignToMe)
				.help(store.canAssignToMe ? "" : "The project's Assignee field does not take your YouTrack user.")
			Toggle("Move to In Progress", isOn: $store.moveToInProgress.sending(\.moveToInProgressChanged))
				.help("Once the worktree exists")
		}

		if let preview = store.state.branchPreview(template: branchTemplate) {
			Text("Branch: \(preview)")
				.scaledFont(.caption)
				.foregroundColor(.secondary)
				.lineLimit(1)
				.truncationMode(.middle)
				.help("The ticket number is known once YouTrack files it")
		}
	}
}

/// Sets a group of conditional fields apart from the ones above it.
private struct ChoiceFieldSectionHeader: View {
	let title: String

	var body: some View {
		HStack(spacing: 6) {
			Text(title)
				.scaledFont(.caption)
				.foregroundColor(.secondary)
				.lineLimit(1)
				.truncationMode(.tail)
				.layoutPriority(1)
			VStack {
				Divider()
			}
		}
		.padding(.top, 4)
		.help(title)
	}
}

/// A new ticket's choice fields, two to a row, each starting at the project's default.
private struct ChoiceFieldsGrid: View {
	let fields: [YouTrackChoiceField]
	let store: StoreOf<NewTicketFormReducer>

	var body: some View {
		Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
			ForEach(Array(stride(from: 0, to: fields.count, by: 2)), id: \.self) { index in
				GridRow {
					cells(for: fields[index])
					if index + 1 < fields.count {
						cells(for: fields[index + 1])
					}
				}
			}
		}
		.controlSize(.small)
	}

	@ViewBuilder
	private func cells(for field: YouTrackChoiceField) -> some View {
		Text(field.name)
			.scaledFont(.caption)
			.foregroundColor(.secondary)
			.lineLimit(1)
			.truncationMode(.tail)
			.gridColumnAlignment(.trailing)
			.help(field.name)
		Group {
			if field.isMultiValue {
				multiValueMenu(for: field)
			}
			else {
				singleValuePicker(for: field)
			}
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.help(field.eventDriven ? "Applied through YouTrack's workflow once the ticket is filed" : "")
	}

	private func singleValuePicker(for field: YouTrackChoiceField) -> some View {
		Picker(field.name, selection: Binding(
			get: { store.state.selection(of: field).first },
			set: { store.send(.fieldValueChanged(field: field.name, values: $0.map { [$0] } ?? [])) }
		)) {
			if field.canBeEmpty || field.defaultValues.isEmpty {
				Text("None").tag(String?.none)
			}
			ForEach(field.values, id: \.self) { value in
				Text(value).tag(String?.some(value))
			}
		}
		.labelsHidden()
	}

	private func multiValueMenu(for field: YouTrackChoiceField) -> some View {
		let selection = store.state.selection(of: field)
		return Menu(selection.isEmpty ? "None" : selection.joined(separator: ", ")) {
			ForEach(field.values, id: \.self) { value in
				Toggle(value, isOn: Binding(
					get: { selection.contains(value) },
					set: { isOn in
						let values = isOn ? selection + [value] : selection.filter { $0 != value }
						store.send(.fieldValueChanged(field: field.name, values: values))
					}
				))
			}
		}
		.labelsHidden()
	}
}

private struct TicketRow: View {
	let ticket: YouTrackIssueSummary

	var body: some View {
		HStack(alignment: .firstTextBaseline, spacing: 8) {
			Text(ticket.id)
				.scaledFont(.body, design: .monospaced)
				.foregroundColor(.secondary)
			Text(ticket.summary)
				.lineLimit(1)
				.truncationMode(.tail)
				.strikethrough(ticket.isResolved)
		}
		.help(ticket.summary)
	}
}

private struct PullRequestRow: View {
	let pullRequest: OpenPullRequest

	var body: some View {
		VStack(alignment: .leading, spacing: 2) {
			HStack(alignment: .firstTextBaseline, spacing: 8) {
				Text(pullRequest.reference)
					.scaledFont(.body, design: .monospaced)
					.foregroundColor(.secondary)
				Text(pullRequest.title)
					.lineLimit(1)
					.truncationMode(.tail)
				if pullRequest.isDraft {
					Text("Draft")
						.scaledFont(.caption2)
						.padding(.horizontal, 4)
						.background(Color.secondary.opacity(0.2), in: RoundedRectangle(cornerRadius: 3))
				}
			}
			Text([pullRequest.headBranchLabel, pullRequest.author].compactMap(\.self).joined(separator: " · "))
				.scaledFont(.caption)
				.foregroundColor(.secondary)
				.lineLimit(1)
				.truncationMode(.middle)
		}
		.help(pullRequest.title)
	}
}

struct CreateWorktreeButtonView: View {
	@Bindable
	var store: StoreOf<CreateWorktreeButtonReducer>

	var body: some View {
		ActionButton(
			icon: .systemImage("plus.square.on.square"),
			tooltip: "Create new worktree",
			color: .green,
			action: { store.send(.showDialog) }
		)
		.opacity(store.isCreating ? 0 : 1)
		.overlay {
			if store.isCreating {
				ProgressView()
					.scaleEffect(0.5)
			}
		}
		.disabled(store.isCreating)
		.sheet(isPresented: $store.showCreateDialog) {
			CreateWorktreeDialogView(store: store)
		}
		.alert($store.scope(\.$errorAlert, action: \.errorAlert))
	}
}

#Preview {
	CreateWorktreeButtonView(
		store: Store(
			initialState: CreateWorktreeButtonReducer.State(
				repositoryPath: "/path/to/repository"
			),
			reducer: {
				CreateWorktreeButtonReducer()
			}
		)
	)
}

private extension OpenPullRequest {
	/// `owner:branch` for a fork's head, as GitHub writes it; the bare branch otherwise.
	var headBranchLabel: String {
		guard isFromFork else {
			return sourceBranch
		}
		return "\(forkOwner ?? "deleted fork"):\(sourceBranch)"
	}
}
