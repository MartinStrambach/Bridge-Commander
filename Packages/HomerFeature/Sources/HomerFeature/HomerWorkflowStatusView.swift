import AppUI
import SwiftUI

/// A LangGraph workflow's state (`workflow-status.tsx`): each node's state, the sub-agent runs
/// the parked nodes dispatched, and the nodes' errors. The console draws the nodes on the
/// workflow's Mermaid graph; here they are its node list — the console's own view of a status
/// without a graph — in the graph's order, and the graph itself is a click away in the web
/// console.
struct HomerWorkflowStatusView: View {
	let status: HomerLangGraphStatus
	let openProcess: (Int) -> Void
	let openGraph: () -> Void

	@State
	private var showsSubs = false

	var body: some View {
		if let error = status.error {
			Text("Workflow status unavailable: \(error)")
				.scaledFont(.callout)
				.foregroundStyle(.red)
				.textSelection(.enabled)
		}
		else if status.nodeStates == nil {
			HStack(spacing: 6) {
				ProgressView()
					.controlSize(.small)
				Text("Loading workflow status…")
					.scaledFont(.callout)
					.foregroundStyle(.secondary)
			}
		}
		else {
			VStack(alignment: .leading, spacing: 8) {
				nodes
				legend
				subs
				if let truncated = status.subsTruncated, !truncated.isEmpty {
					Text("Older sub history not shown for: \(truncated.joined(separator: ", "))")
						.scaledFont(.caption)
						.foregroundStyle(.secondary)
				}
				ForEach(status.nodes.filter { status.errors?[$0.name] != nil }, id: \.name) { node in
					Text("\(Text(node.name + ":").fontWeight(.medium)) \(status.errors?[node.name] ?? "")")
						.scaledFont(.callout)
						.foregroundStyle(.red)
						.textSelection(.enabled)
				}
			}
		}
	}

	private var nodes: some View {
		VStack(alignment: .leading, spacing: 4) {
			ForEach(status.nodes, id: \.name) { node in
				HStack(spacing: 6) {
					HomerWorkflowStateDot(state: node.state, subsFinished: status.subsFinished(node: node.name))
					Text(node.name)
						.scaledFont(.callout, design: .monospaced)
						.fontWeight(.medium)
					Text(node.state)
						.scaledFont(.callout)
						.foregroundStyle(.secondary)
					if let commands = commandStates(of: node.name), !commands.isEmpty {
						HomerCommandDots(states: commands)
					}
				}
			}
		}
	}

	private var legend: some View {
		HomerFlowLayout(spacing: 12) {
			ForEach(HomerWorkflowStateDot.legend, id: \.label) { entry in
				HStack(spacing: 4) {
					HomerWorkflowStateDot(state: entry.state, subsFinished: entry.subsFinished)
					Text(entry.label)
				}
			}
			Text("thread \(status.threadId)")
				.scaledFont(.caption, design: .monospaced)
				.textSelection(.enabled)
			if status.mermaid != nil {
				Button("Show Graph", action: openGraph)
					.buttonStyle(.link)
					.help("Open the run in the web console, which draws the workflow's graph")
			}
		}
		.scaledFont(.caption)
		.foregroundStyle(.secondary)
	}

	@ViewBuilder
	private var subs: some View {
		let subs = status.allSubs
		if !subs.isEmpty {
			// Folded by default: a node keeps every sub it ever dispatched, so the list grows for
			// the life of the thread, and the node rows already carry each one's progress.
			VStack(alignment: .leading, spacing: 4) {
				Button {
					showsSubs.toggle()
				} label: {
					HStack(spacing: 4) {
						Image(systemName: showsSubs ? "chevron.down" : "chevron.right")
							.frame(width: 10)
						Text("\(subs.count { $0.sub.status == "FINISHED" })/\(subs.count) subs finished")
					}
					.contentShape(Rectangle())
				}
				.buttonStyle(.plain)

				if showsSubs {
					ForEach(subs, id: \.sub.interruptId) { entry in
						HStack(spacing: 4) {
							Text(entry.node + ":")
								.fontWeight(.medium)
							Text(entry.sub.agentName ?? "sub")
							if let processId = entry.sub.processId {
								Button("#\(processId)") { openProcess(processId) }
									.buttonStyle(.link)
									.help("Open run #\(processId)")
							}
							// A resolved node keeps its subs, and an old one may have left the
							// process store by now.
							Text("— \(entry.sub.status ?? "purged")")
							if let commands = entry.sub.commands, !commands.isEmpty {
								HomerCommandDots(states: commands.map(\.state), labels: commands.map(\.label))
							}
						}
						.padding(.leading, 14)
					}
				}
			}
			.scaledFont(.caption)
			.foregroundStyle(.secondary)
		}
	}

	/// The commands of a node's sub runs, in order — the dots the console pins to the node's box.
	private func commandStates(of node: String) -> [String]? {
		status.subs?[node]?.flatMap { ($0.commands ?? []).map(\.state) }
	}
}

/// A node's state as the console colors it: done green, failed red, parked amber, pending blue,
/// and a parked node whose sub runs all finished green ringed in amber.
struct HomerWorkflowStateDot: View {
	let state: String
	var subsFinished = false

	static let legend: [(label: String, state: String, subsFinished: Bool)] = [
		("done", "done", false),
		("failed", "failed", false),
		("parked", "parked", false),
		("sub finished", "parked", true),
		("pending", "pending", false),
	]

	var body: some View {
		Circle()
			.fill(subsFinished ? .green : color)
			.overlay {
				if subsFinished {
					Circle().strokeBorder(.orange, lineWidth: 1.5)
				}
			}
			.frame(width: 9, height: 9)
	}

	private var color: Color {
		switch state {
		case "done":
			.green
		case "failed":
			.red
		case "parked":
			.orange
		case "pending":
			.blue
		default:
			.secondary.opacity(0.4)
		}
	}
}

/// One small square per command of a sub run, colored by how it went — the newest last.
struct HomerCommandDots: View {
	let states: [String]
	var labels: [String]?

	/// Beyond this the oldest are dropped: the newest and the running ones say the most.
	private static let limit = 40

	var body: some View {
		let shown = Array(states.enumerated().suffix(Self.limit))
		HStack(spacing: 2) {
			ForEach(shown, id: \.offset) { index, state in
				RoundedRectangle(cornerRadius: 1.5)
					.fill(Self.color(state))
					.frame(width: 7, height: 7)
					.opacity(state == "running" ? 0.6 : 1)
					.help(labels.map { "\($0[index]): \(state)" } ?? state)
			}
		}
	}

	static func color(_ state: String) -> Color {
		switch state {
		case "ok":
			.green
		case "failed":
			.red
		case "running":
			.blue
		default:
			.gray
		}
	}
}
