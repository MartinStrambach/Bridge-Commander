import AppKit
import AppUI
import ComposableArchitecture
import SwiftUI

/// The console's process table (`components/processes/process-table.tsx`) as a list. A row
/// opens the web console's process page, which has the logs, artifacts and workflow graph.
struct HomerProcessListView: View {
	@Bindable
	var store: StoreOf<HomerConsoleReducer>

	var body: some View {
		VStack(spacing: 0) {
			filterBar
			Divider()
			if let error = store.processesError {
				HomerErrorBanner(message: error)
				Divider()
			}
			list
		}
	}

	// MARK: - Filters

	private var filterBar: some View {
		HStack(spacing: 10) {
			Picker("Runs", selection: $store.rootsOnly) {
				Text("All runs").tag(false)
				Text("Root runs").tag(true)
			}
			.pickerStyle(.segmented)
			.labelsHidden()
			.fixedSize()
			.help("Root runs hides the runs that other runs started")

			Divider()
				.frame(height: 18)

			ForEach(HomerProcessStatus.filterable, id: \.self) { status in
				statusChip(status)
			}

			if !store.statusFilter.isEmpty {
				Button("Clear") { store.send(.statusFilterCleared) }
					.buttonStyle(.link)
					.scaledFont(.callout)
			}

			Spacer()

			if store.hasLoadedProcesses {
				Text("\(store.processes.count) of \(store.processTotal)")
					.scaledFont(.subheadline)
					.foregroundStyle(.secondary)
					.monospacedDigit()
			}
		}
		.padding(.horizontal)
		.padding(.vertical, 8)
	}

	private func statusChip(_ status: HomerProcessStatus) -> some View {
		let isOn = store.statusFilter.contains(status)
		return Button {
			store.send(.statusFilterToggled(status))
		} label: {
			Text(status.title)
				.scaledFont(.caption)
				.fontWeight(.semibold)
				.padding(.horizontal, 9)
				.padding(.vertical, 3)
				.foregroundStyle(isOn ? Color.white : Color.primary)
				.background(isOn ? Color.accentColor : Color.clear, in: Capsule())
				.overlay(Capsule().strokeBorder(isOn ? Color.clear : Color.secondary.opacity(0.4)))
				.contentShape(Capsule())
		}
		.buttonStyle(.plain)
		.help(isOn ? "Stop filtering by \(status.title)" : "Show only \(status.title) runs")
	}

	// MARK: - List

	@ViewBuilder
	private var list: some View {
		if !store.hasLoadedProcesses {
			ProgressView("Loading processes…")
				.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
		else if store.processes.isEmpty {
			EmptyStateView(
				title: "No Processes",
				systemImage: "tray",
				description: store.statusFilter.isEmpty ? "No runs yet." : "No runs match the filter."
			)
		}
		else {
			List {
				ForEach(store.processes) { process in
					HomerProcessRow(process: process)
						.contentShape(Rectangle())
						.onTapGesture { store.send(.processTapped(processId: process.id)) }
						.contextMenu { contextMenu(for: process) }
				}

				if store.canLoadMoreProcesses {
					HStack {
						Spacer()
						Button("Load More") { store.send(.loadMoreProcessesTapped) }
							.buttonStyle(.scaledBordered)
						Spacer()
					}
					.padding(.vertical, 6)
				}
			}
			.listStyle(.inset)
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
		Divider()
		Button {
			NSPasteboard.general.clearContents()
			NSPasteboard.general.setString(String(process.id), forType: .string)
		} label: {
			Label("Copy Process ID", systemImage: "doc.on.doc")
		}
	}
}

// MARK: - Row

struct HomerProcessRow: View {
	let process: HomerProcess

	var body: some View {
		HStack(alignment: .firstTextBaseline, spacing: 10) {
			Text(verbatim: "#\(process.id)")
				.scaledFont(.body, design: .monospaced)
				.foregroundStyle(.secondary)
				.frame(minWidth: 60, alignment: .leading)

			VStack(alignment: .leading, spacing: 2) {
				HStack(spacing: 6) {
					Text(process.agentName)
						.scaledFont(.body)
						.fontWeight(.semibold)
						.lineLimit(1)
					HomerStatusBadge(status: process.status)
					if let questions = process.openQuestions, questions > 0 {
						Label("\(questions)", systemImage: "questionmark.bubble.fill")
							.scaledFont(.caption)
							.fontWeight(.semibold)
							.foregroundStyle(.white)
							.padding(.horizontal, 6)
							.padding(.vertical, 1)
							.background(.orange, in: Capsule())
							.help("\(questions) open \(questions == 1 ? "question" : "questions") waiting for an answer")
					}
				}
				if let tags = process.tags, !tags.isEmpty {
					Text(tags.joined(separator: "  "))
						.scaledFont(.caption)
						.foregroundStyle(.secondary)
						.lineLimit(1)
				}
			}

			Spacer(minLength: 12)

			if let lastCommand = process.lastCommand {
				HStack(spacing: 4) {
					lastCommandIcon(lastCommand.outcome)
					Text(lastCommand.label)
						.lineLimit(1)
						.truncationMode(.middle)
				}
				.scaledFont(.callout)
				.foregroundStyle(.secondary)
				.frame(maxWidth: 220, alignment: .trailing)
			}

			if let statusDate = process.statusDate {
				Text(statusDate, format: .relative(presentation: .named))
					.scaledFont(.callout)
					.foregroundStyle(.secondary)
					.frame(minWidth: 90, alignment: .trailing)
					.help(statusDate.formatted(date: .abbreviated, time: .standard))
			}
		}
		.padding(.vertical, 4)
	}

	@ViewBuilder
	private func lastCommandIcon(_ outcome: HomerProcess.LastCommandOutcome) -> some View {
		switch outcome {
		case .running:
			ProgressView()
				.controlSize(.mini)
		case .succeeded:
			Image(systemName: "checkmark")
				.foregroundStyle(.green)
		case .failed:
			Image(systemName: "xmark")
				.foregroundStyle(.red)
		case .skipped:
			Image(systemName: "minus.circle")
		}
	}
}
