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
		.frame(width: 520)
	}

	// MARK: - Branch

	@ViewBuilder
	private var branchSourceContent: some View {
		baseBranchPicker

		Toggle("Create new branch", isOn: $store.createNewBranch)

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
			.disabled(store.filteredBranches.isEmpty)
		}
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
				listPlaceholder(store.pullRequests.isEmpty ? "No open PRs/MRs" : "No matching PRs/MRs")
			}
		}

		if let pullRequest = store.selectedPullRequest {
			Text("Checks out \(pullRequest.sourceBranch)")
				.scaledFont(.caption)
				.foregroundColor(.secondary)
				.lineLimit(1)
				.truncationMode(.middle)
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
				"Prompt for Claude (optional)",
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
			Text([pullRequest.sourceBranch, pullRequest.author].compactMap(\.self).joined(separator: " · "))
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
