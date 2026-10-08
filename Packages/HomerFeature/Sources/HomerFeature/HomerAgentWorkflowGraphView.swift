import AppKit
import AppUI
import ComposableArchitecture
import SwiftUI

/// The sheet of an agent's workflow graphs: one per LangGraph command, labelled when there are
/// several.
struct HomerAgentWorkflowGraphView: View {
	let store: StoreOf<HomerAgentWorkflowGraphReducer>

	var body: some View {
		VStack(alignment: .leading, spacing: 14) {
			VStack(alignment: .leading, spacing: 4) {
				Text("Workflow Graph: \(store.agentName)")
					.scaledFont(.title3)
					.fontWeight(.semibold)
				Text("LangGraph command structure")
					.scaledFont(.callout)
					.foregroundStyle(.secondary)
			}

			content
				.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

			HStack {
				if store.isLoading {
					ProgressView()
						.controlSize(.small)
				}
				if let url = HomerEndpoint.pageURL(
					baseURL: store.baseURL,
					path: HomerAgent(name: store.agentName).consolePath
				) {
					Button("Open in Browser") {
						NSWorkspace.shared.open(url)
					}
					.buttonStyle(.link)
					.scaledFont(.callout)
					.help("Open the agent's page in the web console")
				}
				Spacer()
				Button("Refresh") { store.send(.refreshTapped) }
					.buttonStyle(.scaledBordered)
					.disabled(store.isLoading)
				Button("Close") { store.send(.closeTapped) }
					.buttonStyle(.scaledBorderedProminent)
					.keyboardShortcut(.cancelAction)
			}
		}
		.padding(20)
		.frame(minWidth: 560, idealWidth: 820, minHeight: 360, idealHeight: 680)
		.task { store.send(.task) }
	}

	@ViewBuilder
	private var content: some View {
		if let error = store.loadError {
			Label("Could not read the workflow: \(error)", systemImage: "exclamationmark.triangle.fill")
				.scaledFont(.callout)
				.foregroundStyle(.red)
				.textSelection(.enabled)
		}
		else if let graphs = store.graphs {
			if graphs.isEmpty {
				EmptyStateView(
					title: "No Workflow",
					systemImage: "point.3.connected.trianglepath.dotted",
					description: "\(store.agentName) has no LangGraph commands."
				)
			}
			else if graphs.count == 1 {
				// One graph takes the whole sheet and scrolls by itself.
				graph(graphs[0], maxHeight: .infinity)
			}
			else {
				ScrollView {
					VStack(alignment: .leading, spacing: 20) {
						ForEach(graphs) { graph in
							VStack(alignment: .leading, spacing: 8) {
								Text(graph.label)
									.scaledFont(.callout, design: .monospaced)
									.textSelection(.enabled)
								self.graph(graph, maxHeight: 520)
							}
						}
					}
				}
			}
		}
		else {
			ProgressView("Loading workflow graph…")
				.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
	}

	@ViewBuilder
	private func graph(_ graph: HomerAgentWorkflowGraph, maxHeight: CGFloat) -> some View {
		if let topology = graph.topology {
			HomerWorkflowGraphView(topology: topology, maxHeight: maxHeight) {
				Text("Graph could not be drawn (\(topology.nodes.count) nodes, \(topology.edges.count) edges).")
					.scaledFont(.callout)
					.foregroundStyle(.secondary)
			}
		}
		else {
			Text(graph.error.map { "Couldn't render graph: \($0)" } ?? "Graph structure unavailable.")
				.scaledFont(.callout)
				.foregroundStyle(.red)
				.textSelection(.enabled)
		}
	}
}
