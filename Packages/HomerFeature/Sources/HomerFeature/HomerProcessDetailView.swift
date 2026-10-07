import AppKit
import AppUI
import ComposableArchitecture
import SwiftUI

/// A run's page in a sheet (`app/(dashboard)/processes/[id]/page.tsx`): its status and actions,
/// runner, open questions, status timeline and executions, each execution's output a click away.
/// The questions are the instance's — answered there, as on the Questions page.
struct HomerProcessDetailView: View {
	@Bindable
	var store: StoreOf<HomerProcessDetailReducer>
	let instanceStore: StoreOf<HomerInstanceReducer>

	@Environment(\.dismiss)
	private var dismiss

	var body: some View {
		VStack(spacing: 0) {
			header
			Divider()
			if let error = store.loadError {
				HomerErrorBanner(message: error)
				Divider()
			}
			content
				.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
		// A fixed ideal size: the page's height changes as executions open and close, and a sheet
		// that followed it would re-measure itself (AppUI's README).
		.frame(minWidth: 820, idealWidth: 1040, minHeight: 560, idealHeight: 800)
		.task { store.send(.task) }
		.sheet(item: $store.scope(\.$output, action: \.output)) { outputStore in
			HomerProcessOutputView(store: outputStore)
		}
		.sheet(item: $store.scope(\.$artifacts, action: \.artifacts)) { artifactsStore in
			HomerArtifactsView(store: artifactsStore)
		}
		.sheet(item: $store.webPage) { page in
			HomerWebPageView(page: page)
		}
		.alert($store.scope(\.$alert, action: \.alert))
	}

	// MARK: - Header

	private var header: some View {
		HStack(spacing: 10) {
			if !store.backStack.isEmpty {
				Button {
					store.send(.backTapped)
				} label: {
					Label("Back to #\(store.backStack.last ?? 0)", systemImage: "chevron.left")
				}
				.buttonStyle(.scaledBordered)
				.keyboardShortcut("[", modifiers: .command)
				.help("Back to run #\(store.backStack.last ?? 0) (⌘[)")
			}

			Text("Process #\(store.processId)")
				.scaledFont(.title3)
				.fontWeight(.semibold)
				.textSelection(.enabled)
			if let process = store.process {
				HomerStatusBadge(status: process.status)
			}
			if store.process == nil, store.loadError == nil {
				ProgressView()
					.controlSize(.small)
			}

			Spacer()

			actions

			Button {
				store.send(.openInWebConsoleTapped)
			} label: {
				Label("Web Console", systemImage: "safari")
			}
			.buttonStyle(.scaledBordered)
			.help("Open this run in the web console — it also draws the workflow graph")

			Button("Done") { dismiss() }
				.buttonStyle(.scaledBorderedProminent)
				.keyboardShortcut(.cancelAction)
		}
		.padding(12)
	}

	@ViewBuilder
	private var actions: some View {
		if store.actionInFlight != nil {
			ProgressView()
				.controlSize(.small)
		}
		if store.process != nil {
			Button {
				store.send(.browseArtifactsTapped)
			} label: {
				Label("Artifacts", systemImage: "doc.on.doc")
			}
			.buttonStyle(.scaledBordered)
			.help("Browse and download the run's artifacts")
		}
		if store.canRetry {
			Button {
				store.send(.retryTapped)
			} label: {
				Label("Retry", systemImage: "arrow.counterclockwise")
			}
			.buttonStyle(.scaledBordered)
			.disabled(store.actionInFlight != nil)
			.help("Start the run again with the same inputs")
		}
		if store.canResume {
			Button {
				store.send(.resumeTapped)
			} label: {
				Label("Resume", systemImage: "forward.end")
			}
			.buttonStyle(.scaledBordered)
			.disabled(store.actionInFlight != nil)
			.help("Start a new run from the workflow's last checkpoint")
		}
		if store.canKill {
			Button("Kill Process", role: .destructive) { store.send(.killTapped) }
				.buttonStyle(.scaledBordered)
				.tint(.red)
				.disabled(store.actionInFlight != nil)
		}
	}

	// MARK: - Content

	@ViewBuilder
	private var content: some View {
		if let process = store.process {
			// A plain stack: a run has a handful of sections and executions.
			ScrollView {
				VStack(alignment: .leading, spacing: 16) {
					summary(process)
					if let runner = process.runner {
						HomerRunnerPanel(runner: runner)
					}
					questions
					timeline(process)
					executions(process)
				}
				.padding()
				.frame(maxWidth: .infinity, alignment: .leading)
			}
		}
		else if store.loadError == nil {
			ProgressView("Loading process details…")
		}
	}

	private func summary(_ process: HomerProcess) -> some View {
		HomerFlowLayout(spacing: 14) {
			Text(process.agentName)
				.scaledFont(.title3)
				.textSelection(.enabled)
			if let owner = process.owner {
				Text("by \(owner)")
					.scaledFont(.callout)
					.foregroundStyle(.secondary)
			}
			// From the cost ledger, not the output: still there once the artifacts are purged.
			if let cost = process.costUsd, cost > 0 {
				Text("\(Text("cost").foregroundStyle(.secondary)) \(Text(HomerFormat.cost(cost)).fontWeight(.medium))")
					.scaledFont(.callout)
			}
			if let tags = process.tags, !tags.isEmpty {
				ForEach(tags, id: \.self) { tag in
					Text(tag)
						.scaledFont(.caption2, design: .monospaced)
						.padding(.horizontal, 6)
						.padding(.vertical, 1)
						.background(Color.secondary.opacity(0.15), in: Capsule())
				}
			}
			if let parent = process.parentProcessId {
				Button("Parent #\(parent)") { store.send(.processLinkTapped(processId: parent)) }
					.buttonStyle(.link)
					.scaledFont(.callout)
			}
			if let trace = process.langfuseTraceUrl.flatMap(URL.init(string:)) {
				Link(destination: trace) {
					Label("Langfuse trace", systemImage: "arrow.up.right.square")
				}
				.scaledFont(.callout)
			}
		}
	}

	@ViewBuilder
	private var questions: some View {
		let questions = instanceStore.questions.filter { $0.processId == store.processId }
		if !questions.isEmpty {
			HomerDetailSection("Questions", subtitle: "The agent asked for operator input") {
				VStack(spacing: 10) {
					ForEach(questions) { question in
						HomerQuestionCard(store: instanceStore, question: question, showsProcessLink: false)
					}
				}
			}
		}
	}

	private func timeline(_ process: HomerProcess) -> some View {
		HomerDetailSection("Status Timeline", subtitle: "History of status changes") {
			VStack(alignment: .leading, spacing: 6) {
				ForEach(Array(process.history.enumerated()), id: \.offset) { _, entry in
					HStack(spacing: 10) {
						Text(HomerFormat.timestamp(entry.timestamp))
							.scaledFont(.callout, design: .monospaced)
							.foregroundStyle(.secondary)
						HomerStatusBadge(status: entry.status)
					}
				}
				if let purgeAt = process.purgeAt {
					Divider()
					HStack(spacing: 10) {
						Text(HomerFormat.timestamp(purgeAt))
							.scaledFont(.callout, design: .monospaced)
							.foregroundStyle(.secondary)
						TimelineView(.periodic(from: .now, by: 30)) { context in
							Text("workspace purge (\(HomerFormat.timeUntil(purgeAt, now: context.date)))")
								.scaledFont(.caption)
								.foregroundStyle(.secondary)
								.padding(.horizontal, 6)
								.padding(.vertical, 1)
								.background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
						}
					}
				}
			}
		}
	}

	private func executions(_ process: HomerProcess) -> some View {
		HomerDetailSection("Executions", subtitle: "Command execution history") {
			if process.executions.isEmpty, process.currentCommand == nil {
				Text("No executions yet")
					.scaledFont(.callout)
					.foregroundStyle(.secondary)
			}
			else {
				VStack(spacing: 8) {
					ForEach(Array(process.executions.enumerated()), id: \.offset) { index, execution in
						HomerExecutionRow(
							store: store,
							index: index,
							execution: execution
						)
					}
					if let command = process.currentCommand {
						HomerCurrentCommandRow(
							store: store,
							command: command,
							commandStart: process.currentCommandStart,
							executionIndex: process.executions.count
						)
					}
				}
			}
		}
	}
}

// MARK: - Sections

/// A titled card of the process page, as the console's `Card`s.
struct HomerDetailSection<Content: View>: View {
	let title: String
	let subtitle: String?
	@ViewBuilder
	let content: () -> Content

	init(_ title: String, subtitle: String? = nil, @ViewBuilder content: @escaping () -> Content) {
		self.title = title
		self.subtitle = subtitle
		self.content = content
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			VStack(alignment: .leading, spacing: 2) {
				Text(title)
					.scaledFont(.headline)
				if let subtitle {
					Text(subtitle)
						.scaledFont(.callout)
						.foregroundStyle(.secondary)
				}
			}
			content()
		}
		.padding(14)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
		.overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.2)))
	}
}

/// Where the run executes (`runner-panel.tsx`): the runner, its pod and phase, the pod's
/// timestamps and why it failed to start.
struct HomerRunnerPanel: View {
	let runner: HomerProcess.Runner

	@State
	private var showsStartupFailure = false

	var body: some View {
		HomerDetailSection("Runner", subtitle: "Execution backend for this process") {
			VStack(alignment: .leading, spacing: 8) {
				HStack(spacing: 8) {
					label("Alias:")
					Text(runner.displayName)
						.scaledFont(.callout, design: .monospaced)
						.foregroundStyle(.secondary)
						.textSelection(.enabled)
					if let phase = runner.podPhase {
						Text(Self.title(podPhase: phase))
							.scaledFont(.caption)
							.fontWeight(.semibold)
							.foregroundStyle(.white)
							.padding(.horizontal, 7)
							.padding(.vertical, 2)
							.background(HomerRunnerView.color(podPhase: phase), in: Capsule())
					}
				}
				if let podName = runner.podName {
					HStack(spacing: 8) {
						label("Pod:")
						Text(podName)
							.scaledFont(.callout, design: .monospaced)
							.foregroundStyle(.secondary)
							.textSelection(.enabled)
						Button {
							NSPasteboard.general.clearContents()
							NSPasteboard.general.setString(podName, forType: .string)
						} label: {
							Image(systemName: "doc.on.doc")
						}
						.buttonStyle(.borderless)
						.help("Copy pod name")
					}
				}
				let times = [("Created:", runner.createdAt), ("Ready:", runner.readyAt), ("Ended:", runner.endedAt)]
					.compactMap { name, time in time.map { (name, $0) } }
				if !times.isEmpty {
					Divider()
					ForEach(times, id: \.0) { name, time in
						HStack(spacing: 8) {
							label(name)
							Text(HomerFormat.timestamp(time))
								.scaledFont(.callout, design: .monospaced)
								.foregroundStyle(.secondary)
						}
					}
				}
				if let failure = runner.startupFailure {
					Divider()
					DisclosureGroup(isExpanded: $showsStartupFailure) {
						VStack(alignment: .leading, spacing: 6) {
							Text(failure.message)
								.foregroundStyle(.red)
							ForEach(Array(failure.events.enumerated()), id: \.offset) { _, event in
								Text("• " + event)
									.scaledFont(.caption, design: .monospaced)
									.foregroundStyle(.secondary)
							}
						}
						.textSelection(.enabled)
						.frame(maxWidth: .infinity, alignment: .leading)
						.padding(.top, 4)
					} label: {
						Text("Startup failure: \(failure.reason)")
							.fontWeight(.medium)
							.foregroundStyle(.red)
					}
				}
			}
			.scaledFont(.callout)
		}
	}

	private func label(_ text: String) -> some View {
		Text(text)
			.scaledFont(.callout)
			.fontWeight(.medium)
	}

	static func title(podPhase: String) -> String {
		podPhase == "KEPT_FOR_DEBUG" ? "Kept for debug" : podPhase.capitalized
	}
}

// MARK: - Executions

/// A finished command (`execution-item.tsx`): its outcome and duration, opened to its times,
/// output files, error and — for the command that ran the workflow — the workflow's state.
struct HomerExecutionRow: View {
	let store: StoreOf<HomerProcessDetailReducer>
	let index: Int
	let execution: HomerProcess.Execution

	private var isExpanded: Bool {
		store.expandedExecutions.contains(index)
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			Button {
				store.send(.executionToggled(index: index))
			} label: {
				HStack(spacing: 8) {
					Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
						.scaledFont(.caption)
						.foregroundStyle(.secondary)
						.frame(width: 12)
					outcomeIcon
					Text(execution.label)
						.scaledFont(.body)
						.fontWeight(.medium)
					Text(execution.skipped == true ? "Skipped" : "Exit code: \(execution.resultCode)")
						.scaledFont(.callout)
						.foregroundStyle(.secondary)
						.help(execution.skipped == true ? execution.errMsg ?? "" : "")
					Spacer()
					if let start = execution.start, let end = execution.end {
						Text(HomerFormat.duration(from: start, to: end))
							.scaledFont(.callout)
							.foregroundStyle(.secondary)
							.monospacedDigit()
					}
				}
				.padding(12)
				.contentShape(Rectangle())
			}
			.buttonStyle(.plain)

			if isExpanded {
				Divider()
				details
					.padding(12)
			}
		}
		.background(Color(nsColor: .textBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
		.overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.2)))
	}

	@ViewBuilder
	private var outcomeIcon: some View {
		if execution.skipped == true {
			Image(systemName: "minus.circle")
				.foregroundStyle(.secondary)
		}
		else if execution.resultCode == 0 {
			Image(systemName: "checkmark")
				.foregroundStyle(.green)
		}
		else {
			Image(systemName: "xmark")
				.foregroundStyle(.red)
		}
	}

	private var details: some View {
		VStack(alignment: .leading, spacing: 8) {
			if let start = execution.start {
				field("Start:") { timestamp(start) }
			}
			if let end = execution.end {
				field("End:") { timestamp(end) }
			}
			field("Stdout:") { outputLinks(execution.stdOut, stream: .stdout) }
			field("Stderr:") { outputLinks(execution.stdErr, stream: .stderr) }
			if let error = execution.errMsg {
				field("Error:") {
					Text(error)
						.foregroundStyle(.red)
						.textSelection(.enabled)
				}
			}
			if execution.label == store.langGraphLabel {
				VStack(alignment: .leading, spacing: 6) {
					Text("Workflow:")
						.fontWeight(.medium)
					HomerWorkflowSlot(store: store)
				}
				.padding(.top, 4)
			}
		}
		.scaledFont(.callout)
	}

	private func field(_ name: String, @ViewBuilder value: () -> some View) -> some View {
		HStack(alignment: .firstTextBaseline, spacing: 6) {
			Text(name)
				.fontWeight(.medium)
			value()
		}
	}

	private func timestamp(_ time: Double) -> some View {
		Text(HomerFormat.timestamp(time))
			.scaledFont(.callout, design: .monospaced)
			.foregroundStyle(.secondary)
	}

	@ViewBuilder
	private func outputLinks(_ path: String?, stream: HomerOutputStream) -> some View {
		if let path {
			HStack(spacing: 6) {
				Button {
					store.send(.viewOutputTapped(executionIndex: index, stream: stream))
				} label: {
					Label("View", systemImage: "eye")
				}
				.buttonStyle(.link)
				Text("|")
					.foregroundStyle(.secondary)
				Button {
					store.send(.downloadTapped(path: path))
				} label: {
					Label(HomerArtifactPath.fileName(path), systemImage: "arrow.down.circle")
						.scaledFont(.callout, design: .monospaced)
				}
				.buttonStyle(.link)
				.disabled(store.downloadingPaths.contains(path))
				.help("Save to Downloads")
				if store.downloadingPaths.contains(path) {
					ProgressView()
						.controlSize(.mini)
				}
			}
		}
		else {
			Text("-")
				.foregroundStyle(.secondary)
		}
	}
}

/// The command running now (`current-command-box.tsx`): its live output, how long it has run,
/// and — when it runs the workflow — the workflow's state under it.
struct HomerCurrentCommandRow: View {
	let store: StoreOf<HomerProcessDetailReducer>
	let command: String
	let commandStart: Double?
	let executionIndex: Int

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			HStack(spacing: 8) {
				ProgressView()
					.controlSize(.small)
				Text(command)
					.scaledFont(.body)
					.fontWeight(.medium)
				Text("Running…")
					.scaledFont(.callout)
					.foregroundStyle(.secondary)
				Button {
					store.send(.viewOutputTapped(executionIndex: executionIndex, stream: .stdout))
				} label: {
					Label("View live output", systemImage: "eye")
				}
				.buttonStyle(.link)
				.scaledFont(.callout)
				if store.liveCommandIsWorkflow {
					Button {
						store.send(.liveWorkflowToggled)
					} label: {
						Label(
							store.isLiveWorkflowExpanded ? "Hide workflow" : "Show workflow",
							systemImage: "point.3.connected.trianglepath.dotted"
						)
					}
					.buttonStyle(.link)
					.scaledFont(.callout)
				}
				Spacer()
				if let commandStart {
					VStack(alignment: .trailing, spacing: 2) {
						Text(HomerFormat.timestamp(commandStart))
						TimelineView(.periodic(from: .now, by: 1)) { context in
							Text(HomerFormat.duration(from: commandStart, to: context.date.timeIntervalSince1970))
								.monospacedDigit()
						}
					}
					.scaledFont(.callout)
					.foregroundStyle(.secondary)
				}
			}
			if store.isLiveWorkflowExpanded, store.liveCommandIsWorkflow {
				Divider()
				HomerWorkflowSlot(store: store)
			}
		}
		.padding(12)
		.background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
		.overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.2)))
	}
}

/// The workflow's state where it is shown, or that it is loading.
struct HomerWorkflowSlot: View {
	let store: StoreOf<HomerProcessDetailReducer>

	var body: some View {
		if let workflow = store.workflow {
			HomerWorkflowStatusView(
				status: workflow,
				openProcess: { store.send(.processLinkTapped(processId: $0)) },
				openGraph: { store.send(.openInWebConsoleTapped) }
			)
		}
		else {
			HStack(spacing: 6) {
				ProgressView()
					.controlSize(.small)
				Text("Loading workflow status…")
					.scaledFont(.callout)
					.foregroundStyle(.secondary)
			}
		}
	}
}
