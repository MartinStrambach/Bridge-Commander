import AppKit
import AppUI
import ComposableArchitecture
import SwiftUI

/// The Agents page of the selected instance (the console's `agents/page.tsx`): a search over
/// the agents' cards, Reload for admins, and Run. `user` decides what it offers (Run, Edit, New
/// Agent, Reload, by the user's grants); the server checks every call again.
struct HomerAgentsView: View {
	@Bindable
	var store: StoreOf<HomerAgentsReducer>
	let user: HomerUser

	var body: some View {
		VStack(spacing: 0) {
			toolbar
			Divider()
			if let error = store.loadError {
				HomerErrorBanner(message: error)
				Divider()
			}
			if let error = store.reloadError {
				HomerAgentDismissableBanner(onDismiss: { store.send(.reloadErrorDismissed) }) {
					Label("Reload failed: \(error)", systemImage: "exclamationmark.triangle.fill")
						.foregroundStyle(.red)
				}
				.background(Color.red.opacity(0.08))
				Divider()
			}
			if let result = store.reloadResult {
				HomerAgentReloadBanner(result: result) { store.send(.reloadResultDismissed) }
				Divider()
			}
			content
		}
		.sheet(
			item: $store.scope(\.$runAgent, action: \.runAgent),
			onDismiss: { store.send(.runSheetDismissed) }
		) { runStore in
			HomerRunAgentView(store: runStore)
		}
	}

	private var toolbar: some View {
		HStack(spacing: 10) {
			HStack(spacing: 6) {
				Image(systemName: "magnifyingglass")
					.foregroundStyle(.secondary)
				TextField("Search agents…", text: $store.searchText)
					.textFieldStyle(.plain)
				if !store.searchText.isEmpty {
					Button {
						store.send(.binding(.set(\.searchText, "")))
					} label: {
						Image(systemName: "xmark.circle.fill")
							.foregroundStyle(.secondary)
					}
					.buttonStyle(.plain)
					.help("Clear the search")
				}
			}
			.padding(.horizontal, 8)
			.padding(.vertical, 4)
			.background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
			.overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.3)))
			.frame(maxWidth: 360)

			Spacer()

			if user.canReloadAgents {
				Button {
					store.send(.reloadTapped)
				} label: {
					Label("Reload", systemImage: "arrow.clockwise")
				}
				.buttonStyle(.scaledBordered)
				.disabled(store.isReloading)
				.help("Read every agent definition from disk again")
				if store.isReloading {
					ProgressView()
						.controlSize(.small)
				}
			}
			if user.canCreateAgents {
				Button {
					store.send(.newAgentTapped)
				} label: {
					Label("New Agent…", systemImage: "plus")
				}
				.buttonStyle(.scaledBordered)
				.help("Create an agent in the web console")
			}
		}
		.scaledFont(.callout)
		.padding(.horizontal)
		.padding(.vertical, 8)
	}

	@ViewBuilder
	private var content: some View {
		if !store.hasLoaded {
			ProgressView("Loading agents…")
				.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
		else if store.filteredAgents.isEmpty {
			EmptyStateView(
				title: "No Agents",
				systemImage: "square.stack.3d.up",
				description: store.searchText.isEmpty ? "No agents available." : "No agents match your search."
			)
		}
		else {
			ScrollView {
				LazyVGrid(
					columns: [GridItem(.adaptive(minimum: 300), spacing: 12, alignment: .top)],
					alignment: .leading,
					spacing: 12
				) {
					ForEach(store.filteredAgents) { agent in
						HomerAgentCard(agent: agent, user: user, store: store)
					}
				}
				.padding()
			}
		}
	}
}

/// The Schedules page of the selected instance (the console's `schedules/page.tsx`): its agents
/// that run on a cron, soonest next run first. Admins only — the console shows it to no one
/// else, and the instance never tells this reducer it is on screen for anyone else.
struct HomerSchedulesView: View {
	let store: StoreOf<HomerAgentsReducer>

	@State
	private var selection: Set<HomerAgent.ID> = []

	var body: some View {
		VStack(spacing: 0) {
			if let error = store.loadError {
				HomerErrorBanner(message: error)
				Divider()
			}
			if !store.hasLoaded {
				ProgressView("Loading schedules…")
					.frame(maxWidth: .infinity, maxHeight: .infinity)
			}
			else if store.schedules.isEmpty {
				EmptyStateView(
					title: "No Scheduled Agents",
					systemImage: "calendar.badge.clock",
					description: "Agents with a cron show up here."
				)
			}
			else {
				table
			}
		}
	}

	private var table: some View {
		Table(store.schedules, selection: $selection) {
			TableColumn("Agent") { agent in
				Button {
					store.send(.agentTapped(agentName: agent.name))
				} label: {
					Text(agent.name)
						.scaledFont(.body)
						.fontWeight(.medium)
				}
				.buttonStyle(.link)
				.help("Open the agent")
			}
			.width(min: 140, ideal: 220)

			TableColumn("Expression") { agent in
				Text(agent.cron?.expression ?? "")
					.scaledFont(.callout, design: .monospaced)
					.textSelection(.enabled)
			}
			.width(min: 100, ideal: 150)

			TableColumn("Timezone") { agent in
				Text(agent.cron?.timezone ?? "")
					.scaledFont(.callout)
					.foregroundStyle(.secondary)
			}
			.width(min: 80, ideal: 130)

			TableColumn("Next run") { agent in
				if let nextRunAt = agent.cron?.nextRunAt {
					VStack(alignment: .leading, spacing: 1) {
						HomerScheduleCountdownText(epochSeconds: nextRunAt)
							.scaledFont(.callout)
						Text(HomerFormat.timestamp(nextRunAt))
							.scaledFont(.caption, design: .monospaced)
							.foregroundStyle(.secondary)
					}
					.padding(.vertical, 2)
				}
				else {
					Text("—")
						.foregroundStyle(.secondary)
				}
			}
			.width(min: 120, ideal: 150)

			TableColumn("Last run") { agent in
				lastRun(agent.cron)
			}
			.width(min: 120, ideal: 150)
		}
		.contextMenu(forSelectionType: HomerAgent.ID.self) { ids in
			if let id = ids.first, let agent = store.agents[id: id] {
				contextMenu(for: agent)
			}
		} primaryAction: { ids in
			if let id = ids.first {
				store.send(.agentTapped(agentName: id))
			}
		}
	}

	@ViewBuilder
	private func lastRun(_ cron: HomerAgent.Cron?) -> some View {
		if let lastRunAt = cron?.lastRunAt {
			if let processId = cron?.lastRunProcessId {
				Button {
					store.send(.processTapped(processId: processId))
				} label: {
					Text(HomerFormat.timestamp(lastRunAt))
						.scaledFont(.callout, design: .monospaced)
				}
				.buttonStyle(.link)
				.help("Open process \(processId)")
			}
			else {
				Text(HomerFormat.timestamp(lastRunAt))
					.scaledFont(.callout, design: .monospaced)
			}
		}
		else {
			Text("Never")
				.scaledFont(.callout)
				.foregroundStyle(.secondary)
		}
	}

	@ViewBuilder
	private func contextMenu(for agent: HomerAgent) -> some View {
		Button {
			store.send(.agentTapped(agentName: agent.name))
		} label: {
			Label("Open Agent", systemImage: "square.stack.3d.up")
		}
		if let processId = agent.cron?.lastRunProcessId {
			Button {
				store.send(.processTapped(processId: processId))
			} label: {
				Label("Open Last Run #\(processId)", systemImage: "doc.text.magnifyingglass")
			}
		}
		Divider()
		if let expression = agent.cron?.expression {
			Button {
				NSPasteboard.general.clearContents()
				NSPasteboard.general.setString(expression, forType: .string)
			} label: {
				Label("Copy Cron Expression", systemImage: "doc.on.doc")
			}
		}
	}
}

/// "in 2h 3m" until a moment, counting down every second (`formatTimeUntil`).
struct HomerScheduleCountdownText: View {
	let epochSeconds: Double

	var body: some View {
		TimelineView(.periodic(from: .now, by: 1)) { context in
			Text(HomerFormat.timeUntil(epochSeconds, now: context.date))
				.monospacedDigit()
		}
	}
}
