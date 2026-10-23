import AppKit
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

	/// The current tab's and the follow-up section's natural heights, which their frames animate to.
	@State
	private var tabHeight: CGFloat?
	@State
	private var followUpHeight: CGFloat?

	private static let heightAnimation = Animation.smooth(duration: 0.25)

	var body: some View {
		VStack(spacing: 0) {
			VStack(alignment: .leading, spacing: 16) {
				header

				Picker("Source", selection: $store.source.sending(\.sourceChanged).animation(Self.heightAnimation)) {
					ForEach(store.availableSources, id: \.self) { source in
						Text(source.title).tag(source)
					}
				}
				.pickerStyle(.segmented)
				.labelsHidden()
				.controlSize(.large)

				// The outgoing tab fades out over the incoming one. The sheet does not animate its own
				// resize, so the stack's height is animated instead, toward the incoming tab's height:
				// the outgoing tab's would keep the stack at the taller of the two until its fade ends.
				ZStack(alignment: .top) {
					let source = store.source
					VStack(alignment: .leading, spacing: 16) {
						switch store.source {
						case .branch:
							branchSourceContent
						case .ticket:
							ticketSourceContent
						case .newTicket:
							DialogSection("New Ticket", systemImage: "square.and.pencil") {
								NewTicketSourceView(
									store: store.scope(\.newTicket, action: \.newTicket),
									branchTemplate: store.ticketBranchNameTemplate
								)
							}
							baseBranchSection
						case .pullRequest:
							pullRequestSourceContent
						}
					}
					.onNaturalHeightChange { height in
						guard source == store.source else { return }
						animate($tabHeight, to: height)
					}
					.id(source)
					.transition(.opacity)
				}
				.modifier(AnimatedHeight(height: tabHeight))

				followUpSection
					.onNaturalHeightChange { animate($followUpHeight, to: $0) }
					.modifier(AnimatedHeight(height: followUpHeight))
			}
			.padding(20)

			footer
		}
		// Grows with the "Start from" menu, which names the selected base branch in full.
		.frame(minWidth: 520, maxWidth: 800)
	}

	// MARK: - Header & footer

	private var header: some View {
		HStack(spacing: 12) {
			RoundedRectangle(cornerRadius: 9, style: .continuous)
				.fill(.green.gradient)
				.frame(width: 38, height: 38)
				.overlay {
					Image(systemName: "plus.square.on.square")
						.font(.system(size: 17, weight: .semibold))
						.foregroundStyle(.white)
				}
				.shadow(color: .green.opacity(0.25), radius: 3, y: 1)

			VStack(alignment: .leading, spacing: 2) {
				Text("New Worktree")
					.scaledFont(.title3)
					.fontWeight(.semibold)
				Label(store.repositoryName, systemImage: "folder")
					.scaledFont(.callout)
					.foregroundStyle(.secondary)
					.lineLimit(1)
					.truncationMode(.middle)
			}
		}
	}

	private var footer: some View {
		HStack {
			Spacer()

			Button("Cancel") {
				store.send(.cancelCreation)
			}
			.buttonStyle(.scaledAutomatic)
			.keyboardShortcut(.cancelAction)

			Button("Create") {
				store.send(.confirmCreation)
			}
			.buttonStyle(.scaledBorderedProminent)
			.keyboardShortcut(.defaultAction)
			.disabled(!store.canCreate)
		}
		.controlSize(.large)
		.padding(.horizontal, 20)
		.padding(.vertical, 14)
		.background(.bar)
		.overlay(alignment: .top) {
			Divider()
		}
	}

	// MARK: - Branch

	@ViewBuilder
	private var branchSourceContent: some View {
		baseBranchSection

		DialogSection(
			"New Branch",
			systemImage: "plus.circle",
			accessory: {
				Toggle("Create new branch", isOn: $store.createNewBranch)
					.toggleStyle(.switch)
					.controlSize(.small)
					.labelsHidden()
			}
		) {
			if store.createNewBranch {
				newBranchNameField
			}
			else {
				sectionNote("Checks out \(store.selectedBaseBranch) as it is")
			}
		}
	}

	/// The base branch, filtered and picked, and where a new branch starts on it.
	private var baseBranchSection: some View {
		DialogSection("Base Branch", systemImage: "arrow.triangle.branch") {
			if store.isLoadingBranches {
				ProgressView()
					.controlSize(.small)
					.frame(maxWidth: .infinity)
			}
			else {
				DialogSearchField(prompt: "Filter branches", text: $store.branchSearchText)

				Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
					GridRow {
						gridLabel("Branch")
						Picker("Branch", selection: $store.selectedBaseBranch) {
							ForEach(store.filteredBranches, id: \.self) { branchInfo in
								Text(branchInfo.name + (branchInfo.isRemoteOnly ? " (remote)" : ""))
									.foregroundColor(branchInfo.isRemoteOnly ? .orange.opacity(0.5) : .green.opacity(0.8))
									.tag(branchInfo.name)
							}
						}
						.pickerStyle(.menu)
						.labelsHidden()
						// A menu wants the width of its longest item, here any branch in the repository;
						// the dialog sizes to the selected one, through the "Start from" menu, instead.
						.frame(idealWidth: 200, maxWidth: .infinity)
						.disabled(store.filteredBranches.isEmpty)
					}

					if store.showsStartPoint {
						GridRow {
							gridLabel("Start from")
							startPointPicker
						}
					}
				}
			}
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
		.labelsHidden()
		.disabled(!store.canChooseStartPoint)
	}

	private var newBranchNameField: some View {
		TextField("Branch name", text: $store.branchName, prompt: Text("Enter branch name"))
			.textFieldStyle(.roundedBorder)
	}

	// MARK: - Ticket

	@ViewBuilder
	private var ticketSourceContent: some View {
		DialogSection(
			"Ticket",
			systemImage: "ticket",
			accessory: {
				ProgressView()
					.controlSize(.small)
					.opacity(store.isSearchingTickets ? 1 : 0)
			}
		) {
			DialogSearchField(
				prompt: "Search YouTrack — empty lists your open tickets",
				text: $store.ticketQuery,
				onSubmit: { store.send(.searchTickets) }
			)

			List(selection: Binding(
				get: { store.selectedTicketId },
				set: { store.send(.ticketSelected($0)) }
			)) {
				ForEach(store.tickets) { ticket in
					TicketRow(ticket: ticket)
						.tag(ticket.id)
				}
			}
			.dialogList(height: 200)
			.overlay {
				if let error = store.ticketSearchError {
					listPlaceholder(error, systemImage: "exclamationmark.triangle", isError: true)
				}
				else if store.tickets.isEmpty, !store.isSearchingTickets {
					listPlaceholder("No matching tickets", systemImage: "ticket")
				}
			}

			if store.selectedTicketId != nil {
				newBranchNameField
			}
		}

		baseBranchSection
	}

	// MARK: - Pull request

	private var pullRequestSourceContent: some View {
		DialogSection(
			"Pull Request",
			systemImage: "arrow.triangle.pull",
			accessory: {
				HStack(spacing: 10) {
					Toggle("Only mine", isOn: $store.onlyMyPullRequests.sending(\.onlyMyPullRequestsChanged))
						.toggleStyle(.switch)
						.controlSize(.mini)
						.scaledFont(.caption)
					if store.isLoadingPullRequests {
						ProgressView()
							.controlSize(.small)
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
			}
		) {
			DialogSearchField(prompt: "Filter by title, branch, number or author", text: $store.pullRequestFilter)

			List(selection: Binding(
				get: { store.selectedPullRequestNumber },
				set: { store.send(.pullRequestSelected($0)) }
			)) {
				ForEach(store.filteredPullRequests) { pullRequest in
					PullRequestRow(pullRequest: pullRequest)
						.tag(pullRequest.number)
				}
			}
			.dialogList(height: 240)
			.overlay {
				if let error = store.pullRequestError {
					listPlaceholder(error, systemImage: "exclamationmark.triangle", isError: true)
				}
				else if store.filteredPullRequests.isEmpty, !store.isLoadingPullRequests {
					listPlaceholder(pullRequestPlaceholder, systemImage: "arrow.triangle.pull")
				}
			}

			if let pullRequest = store.selectedPullRequest {
				sectionNote("Checks out \(pullRequest.headBranchLabel)\(pullRequest.isFromFork ? " from a fork" : "")")
			}
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

	private var followUpSection: some View {
		DialogSection("After Creating", systemImage: "arrow.forward.circle") {
			Picker("After creating", selection: $store.followUp.sending(\.followUpChanged)) {
				ForEach(WorktreeCreationFollowUp.allCases, id: \.self) { followUp in
					Text(followUp.title).tag(followUp)
				}
			}
			.pickerStyle(.segmented)
			.labelsHidden()

			if store.followUp == .runClaude {
				TextField(
					"Prompt for Claude",
					text: $store.claudePrompt,
					prompt: Text(store.source == .newTicket ? "Prompt for Claude (blank: work on the new ticket)" : "Prompt for Claude (optional)"),
					axis: .vertical
				)
				.textFieldStyle(.roundedBorder)
				.lineLimit(2 ... 4)
			}
		}
	}

	// MARK: - Helpers

	/// Moves a frame to a section's new natural height, at once the first time it is measured.
	private func animate(_ height: Binding<CGFloat?>, to newHeight: CGFloat) {
		guard height.wrappedValue != nil else {
			height.wrappedValue = newHeight
			return
		}
		withAnimation(Self.heightAnimation) {
			height.wrappedValue = newHeight
		}
	}

	private func gridLabel(_ text: String) -> some View {
		Text(text)
			.scaledFont(.callout)
			.foregroundStyle(.secondary)
			.gridColumnAlignment(.trailing)
	}

	private func sectionNote(_ text: String) -> some View {
		Text(text)
			.scaledFont(.caption)
			.foregroundStyle(.secondary)
			.lineLimit(1)
			.truncationMode(.middle)
	}

	private func listPlaceholder(_ text: String, systemImage: String, isError: Bool = false) -> some View {
		VStack(spacing: 6) {
			Image(systemName: systemImage)
				.scaledFont(.title2)
				.foregroundStyle(isError ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))
			Text(text)
				.scaledFont(.callout)
				.foregroundColor(isError ? .orange : .secondary)
				.multilineTextAlignment(.center)
		}
		.padding()
	}
}

/// A frame of the given height, top-aligned and clipped, that passes through every step of an
/// animation. SwiftUI lays out each step, so the sheet follows it; it does not animate a resize of
/// its own. A nil height leaves the content at its natural height.
private struct AnimatedHeight: ViewModifier, Animatable {
	var height: CGFloat?

	nonisolated var animatableData: CGFloat {
		get { height ?? 0 }
		set { height = newValue }
	}

	func body(content: Content) -> some View {
		content
			.frame(height: height, alignment: .top)
			.clipped()
	}
}

/// A titled, rounded group of the dialog's controls, with an optional control at the title's end.
private struct DialogSection<Accessory: View, Content: View>: View {
	let title: String
	let systemImage: String
	@ViewBuilder
	let accessory: Accessory
	@ViewBuilder
	let content: Content

	init(
		_ title: String,
		systemImage: String,
		@ViewBuilder accessory: () -> Accessory = { EmptyView() },
		@ViewBuilder content: () -> Content
	) {
		self.title = title
		self.systemImage = systemImage
		self.accessory = accessory()
		self.content = content()
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			HStack(spacing: 6) {
				Label(title, systemImage: systemImage)
					.scaledFont(.subheadline)
					.fontWeight(.semibold)
					.foregroundStyle(.secondary)
				Spacer(minLength: 8)
				accessory
			}
			.padding(.horizontal, 4)
			// Keeps the cards aligned whether or not the title has a control beside it.
			.frame(minHeight: 18)

			let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
			VStack(alignment: .leading, spacing: 10) {
				content
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding(12)
			.background(Color.primary.opacity(0.035), in: shape)
			.overlay {
				shape.strokeBorder(Color.primary.opacity(0.08))
			}
		}
	}
}

/// A text field drawn like a search field: a magnifying glass, the text and a clear button.
private struct DialogSearchField: View {
	let prompt: String
	@Binding
	var text: String
	var onSubmit: () -> Void = {}

	@FocusState
	private var isFocused: Bool

	var body: some View {
		let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
		HStack(spacing: 6) {
			Image(systemName: "magnifyingglass")
				.foregroundStyle(.secondary)
			TextField(prompt, text: $text)
				.textFieldStyle(.plain)
				.focused($isFocused)
				.onSubmit(onSubmit)
			if !text.isEmpty {
				Button {
					text = ""
				} label: {
					Image(systemName: "xmark.circle.fill")
						.foregroundStyle(.tertiary)
				}
				.buttonStyle(.plain)
				.help("Clear")
			}
		}
		.padding(.horizontal, 8)
		.padding(.vertical, 5)
		.background(Color(nsColor: .textBackgroundColor), in: shape)
		.overlay {
			shape.strokeBorder(
				isFocused ? Color.accentColor : Color.primary.opacity(0.12),
				lineWidth: isFocused ? 2 : 1
			)
		}
		.animation(.easeOut(duration: 0.12), value: isFocused)
	}
}

private extension View {
	/// Lays the view out at its natural height and reports that height whenever it changes.
	func onNaturalHeightChange(_ action: @escaping (CGFloat) -> Void) -> some View {
		fixedSize(horizontal: false, vertical: true)
			.onGeometryChange(for: CGFloat.self, of: \.size.height, action: action)
	}

	/// A selectable list inset into a section, on the text background with rounded corners.
	func dialogList(height: CGFloat) -> some View {
		let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
		return listStyle(.inset)
			.scrollContentBackground(.hidden)
			.background(Color(nsColor: .textBackgroundColor), in: shape)
			.clipShape(shape)
			.overlay {
				shape.strokeBorder(Color.primary.opacity(0.1))
			}
			.frame(height: height)
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
						.fontWeight(.medium)
						.foregroundStyle(.secondary)
						.padding(.horizontal, 6)
						.padding(.vertical, 1)
						.background(Color.secondary.opacity(0.16), in: Capsule())
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
