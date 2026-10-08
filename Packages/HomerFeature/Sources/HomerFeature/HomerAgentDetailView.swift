import AppKit
import AppUI
import ComposableArchitecture
import SwiftUI

/// An agent's page (the console's `agents/[name]/page.tsx`), in place of the Agents or Schedules
/// page that opened it: Back, the agent with Edit and Run, then its run history, parameters and
/// workflow graphs, one section at a time. `user` decides what it offers; the server checks
/// every call again.
struct HomerAgentDetailView: View {
	@Bindable
	var store: StoreOf<HomerAgentDetailReducer>
	let user: HomerUser

	var body: some View {
		VStack(spacing: 0) {
			navigationBar
			Divider()
			if let agent = store.agent {
				header(agent)
				Divider()
				content(agent)
			}
			else {
				ContentUnavailableView {
					Label("Agent Not Found", systemImage: "questionmark.square.dashed")
				} description: {
					Text("No agent named \(store.agentName). A reload may have removed it.")
				} actions: {
					Button(backTitle) { store.send(.backTapped) }
						.buttonStyle(.scaledBordered)
				}
			}
		}
		.alert($store.scope(\.$alert, action: \.alert))
	}

	private var backTitle: String {
		store.openedFrom == .schedules ? "Schedules" : "Agents"
	}

	// MARK: - Header

	private var navigationBar: some View {
		HStack(spacing: 10) {
			Button {
				store.send(.backTapped)
			} label: {
				Label(backTitle, systemImage: "chevron.left")
			}
			.buttonStyle(.scaledBordered)
			.keyboardShortcut("[", modifiers: .command)
			.help("Back to \(backTitle) (⌘[)")

			Spacer()

			if let url = HomerEndpoint.pageURL(
				baseURL: store.baseURL,
				path: HomerAgent(name: store.agentName).consolePath
			) {
				Button {
					NSWorkspace.shared.open(url)
				} label: {
					Label("Open in Browser", systemImage: "safari")
				}
				.buttonStyle(.scaledBordered)
				.help("Open the agent's page in the web console")
			}
		}
		.scaledFont(.callout)
		.padding(.horizontal)
		.padding(.vertical, 8)
	}

	private func header(_ agent: HomerAgent) -> some View {
		VStack(alignment: .leading, spacing: 10) {
			HStack(alignment: .firstTextBaseline, spacing: 10) {
				Text(agent.name)
					.scaledFont(.title2)
					.fontWeight(.bold)
					.textSelection(.enabled)
				if agent.cron != nil {
					Label("Scheduled", systemImage: "clock")
						.scaledFont(.caption)
						.padding(.horizontal, 6)
						.padding(.vertical, 1)
						.background(Color.secondary.opacity(0.15), in: Capsule())
				}

				Spacer()

				if user.canEdit(agent) {
					Button {
						store.send(.editTapped)
					} label: {
						Label("Edit", systemImage: "pencil")
					}
					.buttonStyle(.scaledBordered)
					.help("Edit \(agent.name)'s files in the web console")
				}
				if user.canRun(agent) {
					Button {
						store.send(.runTapped)
					} label: {
						Label("Run…", systemImage: "play.fill")
					}
					.buttonStyle(.scaledBorderedProminent)
					.help("Run agent \(agent.name)")
				}
			}
			if let description = agent.description, !description.isEmpty {
				Text(description)
					.scaledFont(.body)
					.foregroundStyle(.secondary)
					.textSelection(.enabled)
					.fixedSize(horizontal: false, vertical: true)
			}
			if let cron = agent.cron {
				cronLine(cron)
			}

			Picker("Section", selection: $store.section.sending(\.sectionSelected)) {
				Text(store.hasLoadedRuns ? "Runs (\(store.runTotal))" : "Runs")
					.tag(HomerAgentDetailReducer.Section.runs)
				Text("Parameters (\(agent.inputs.count))")
					.tag(HomerAgentDetailReducer.Section.parameters)
				Text("Workflow Graph")
					.tag(HomerAgentDetailReducer.Section.workflow)
			}
			.pickerStyle(.segmented)
			.labelsHidden()
			.fixedSize()
		}
		.padding(.horizontal)
		.padding(.vertical, 12)
	}

	/// The schedule, which the console's page shows only as the badge: the cron, its next run
	/// counting down, and the last run, opening the run it started.
	private func cronLine(_ cron: HomerAgent.Cron) -> some View {
		HStack(spacing: 12) {
			HStack(spacing: 4) {
				Text(cron.expression)
					.scaledFont(.callout, design: .monospaced)
					.textSelection(.enabled)
				if !cron.timezone.isEmpty {
					Text("(\(cron.timezone))")
				}
			}
			if let nextRunAt = cron.nextRunAt {
				HStack(spacing: 4) {
					Text("Next:")
					HomerScheduleCountdownText(epochSeconds: nextRunAt)
				}
				.help(HomerFormat.timestamp(nextRunAt))
			}
			HStack(spacing: 4) {
				Text("Last:")
				if let lastRunAt = cron.lastRunAt {
					if let processId = cron.lastRunProcessId {
						Button(HomerFormat.timestamp(lastRunAt)) {
							store.send(.processTapped(processId: processId))
						}
						.buttonStyle(.link)
						.help("Open process \(processId)")
					}
					else {
						Text(HomerFormat.timestamp(lastRunAt))
					}
				}
				else {
					Text("Never")
				}
			}
		}
		.scaledFont(.callout)
		.foregroundStyle(.secondary)
	}

	// MARK: - Sections

	@ViewBuilder
	private func content(_ agent: HomerAgent) -> some View {
		switch store.section {
		case .runs:
			runs
		case .parameters:
			parameters(agent)
		case .workflow:
			workflow
		}
	}

	@ViewBuilder
	private func parameters(_ agent: HomerAgent) -> some View {
		if agent.inputs.isEmpty {
			EmptyStateView(
				title: "No Parameters",
				systemImage: "slider.horizontal.3",
				description: "\(agent.name) takes no inputs when run."
			)
		}
		else {
			ScrollView {
				VStack(alignment: .leading, spacing: 14) {
					Text("Inputs accepted when running this agent")
						.scaledFont(.callout)
						.foregroundStyle(.secondary)
					ForEach(agent.inputs) { input in
						VStack(alignment: .leading, spacing: 3) {
							HStack(spacing: 6) {
								HomerAgentInputHeader(input: input)
								if input.source != .unknown {
									HomerAgentBadge(text: input.source.rawValue)
										.help("Sent as a \(input.source.rawValue) value")
								}
							}
							HomerAgentInputDetails(input: input)
						}
					}
				}
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding()
			}
		}
	}

	private var workflow: some View {
		let graphStore = store.scope(\.workflowGraph, action: \.workflowGraph)
		return VStack(alignment: .leading, spacing: 10) {
			HStack(spacing: 8) {
				Text("LangGraph command structure")
					.scaledFont(.callout)
					.foregroundStyle(.secondary)
				if graphStore.isLoading {
					ProgressView()
						.controlSize(.small)
				}
				Spacer()
				Button("Refresh") { graphStore.send(.refreshTapped) }
					.buttonStyle(.scaledBordered)
					.disabled(graphStore.isLoading)
					.help("Inspect the agent's LangGraph commands again")
			}
			HomerAgentWorkflowGraphContent(store: graphStore)
				.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
		}
		.padding()
	}

	// MARK: - Run history

	@ViewBuilder
	private var runs: some View {
		VStack(spacing: 0) {
			if let error = store.runsError {
				HomerErrorBanner(message: error)
				Divider()
			}
			if !store.hasLoadedRuns {
				ProgressView("Loading runs…")
					.frame(maxWidth: .infinity, maxHeight: .infinity)
			}
			else if store.runs.isEmpty {
				EmptyStateView(
					title: "No Runs",
					systemImage: "tray",
					description: "\(store.agentName) has not run yet."
				)
			}
			else {
				HomerAgentRunTable(store: store, user: user)
				Divider()
				runsFooter
			}
		}
	}

	private var runsFooter: some View {
		HStack(spacing: 12) {
			Text("Showing \(store.runs.count) of \(store.runTotal) runs")
				.foregroundStyle(.secondary)
				.monospacedDigit()
			HStack(spacing: 4) {
				Text("Total cost:")
					.foregroundStyle(.secondary)
				Text(HomerFormat.cost(store.listedCostUsd))
					.scaledFont(.callout, design: .monospaced)
					.fontWeight(.medium)
			}
			.help("What the listed runs cost together")
			Spacer()
			if store.canLoadMoreRuns {
				Button("Load More") { store.send(.loadMoreRunsTapped) }
					.buttonStyle(.scaledBordered)
			}
		}
		.scaledFont(.callout)
		.padding(.horizontal)
		.padding(.vertical, 6)
	}
}

/// The agent's runs, with the process list's columns (`process-table.tsx`, which the console's
/// page reuses) except the agent's name, which every row would repeat; its tags get a column of
/// their own.
private struct HomerAgentRunTable: View {
	let store: StoreOf<HomerAgentDetailReducer>
	let user: HomerUser

	@State
	private var selection: Set<HomerProcess.ID> = []

	var body: some View {
		Table(store.runs, selection: $selection) {
			TableColumn("ID") { process in
				Button {
					store.send(.processTapped(processId: process.id))
				} label: {
					Text(verbatim: "\(process.id)")
						.scaledFont(.body, design: .monospaced)
				}
				.buttonStyle(.link)
				.help("Open process \(process.id)")
			}
			.width(min: 56, ideal: 70, max: 100)

			TableColumn("Status") { process in
				HStack(spacing: 6) {
					HomerStatusBadge(status: process.status)
					HomerQuestionCountBadge(count: process.openQuestions ?? 0)
				}
			}
			.width(min: 90, ideal: 130)

			TableColumn("Status Time") { process in
				if let timestamp = process.history.last?.timestamp {
					Text(HomerFormat.timestamp(timestamp))
						.scaledFont(.callout, design: .monospaced)
						.foregroundStyle(.secondary)
				}
				else {
					placeholder
				}
			}
			.width(min: 120, ideal: 140)

			TableColumn("Last Command") { process in
				HomerLastCommandView(process: process)
			}
			.width(min: 100, ideal: 180)

			TableColumn("Cost") { process in
				if let cost = process.costUsd, cost > 0 {
					Text(HomerFormat.cost(cost))
						.scaledFont(.callout, design: .monospaced)
				}
				else {
					placeholder
				}
			}
			.width(min: 60, ideal: 80)

			TableColumn("Runner") { process in
				HomerRunnerView(runner: process.runner)
			}
			.width(min: 70, ideal: 110)

			TableColumn("Tags") { process in
				if let tags = process.tags, !tags.isEmpty {
					Text(tags.joined(separator: ", "))
						.scaledFont(.caption, design: .monospaced)
						.foregroundStyle(.secondary)
						.lineLimit(1)
						.truncationMode(.tail)
						.help(tags.joined(separator: "\n"))
				}
				else {
					placeholder
				}
			}
			.width(min: 60, ideal: 140)

			TableColumn("Purge") { process in
				if let purgeAt = process.purgeAt {
					Text(HomerFormat.timeUntil(purgeAt, now: Date()))
						.scaledFont(.callout)
						.foregroundStyle(.secondary)
						.help(HomerFormat.timestamp(purgeAt))
				}
				else {
					Text("—")
						.foregroundStyle(.secondary)
				}
			}
			.width(min: 60, ideal: 80)

			TableColumn("Actions") { process in
				actions(for: process)
			}
			.width(min: 70, ideal: 80)
		}
		.contextMenu(forSelectionType: HomerProcess.ID.self) { ids in
			if let id = ids.first, let process = store.runs[id: id] {
				contextMenu(for: process)
			}
		} primaryAction: { ids in
			if let id = ids.first {
				store.send(.processTapped(processId: id))
			}
		}
	}

	private var placeholder: some View {
		Text("-")
			.foregroundStyle(.secondary)
	}

	@ViewBuilder
	private func actions(for process: HomerProcess) -> some View {
		if store.runActionsInFlight.contains(process.id) {
			ProgressView()
				.controlSize(.small)
		}
		else if process.isKillable, user.canKill(process) {
			Button("Kill", role: .destructive) { store.send(.killTapped(processId: process.id)) }
				.buttonStyle(.scaledBordered)
				.controlSize(.small)
				.tint(.red)
		}
		else if process.isRetryable, user.canRetry(process) {
			Button {
				store.send(.retryTapped(processId: process.id))
			} label: {
				Label("Retry", systemImage: "arrow.counterclockwise")
			}
			.buttonStyle(.scaledBordered)
			.controlSize(.small)
			.help("Start the run again with the same inputs")
		}
	}

	@ViewBuilder
	private func contextMenu(for process: HomerProcess) -> some View {
		Button {
			store.send(.processTapped(processId: process.id))
		} label: {
			Label("Open Process", systemImage: "doc.text.magnifyingglass")
		}
		if let url = HomerEndpoint.pageURL(baseURL: store.baseURL, path: "processes/\(process.id)") {
			Button {
				NSWorkspace.shared.open(url)
			} label: {
				Label("Open in Browser", systemImage: "safari")
			}
		}
		if let parent = process.parentProcessId {
			Button {
				store.send(.processTapped(processId: parent))
			} label: {
				Label("Open Parent #\(parent)", systemImage: "arrow.turn.left.up")
			}
		}
		Divider()
		Button {
			NSPasteboard.general.clearContents()
			NSPasteboard.general.setString(String(process.id), forType: .string)
		} label: {
			Label("Copy Process ID", systemImage: "doc.on.doc")
		}
		if process.isKillable, user.canKill(process) {
			Divider()
			Button(role: .destructive) {
				store.send(.killTapped(processId: process.id))
			} label: {
				Label("Kill…", systemImage: "xmark.octagon")
			}
		}
		else if process.isRetryable, user.canRetry(process) {
			Divider()
			Button {
				store.send(.retryTapped(processId: process.id))
			} label: {
				Label("Retry", systemImage: "arrow.counterclockwise")
			}
		}
	}
}
