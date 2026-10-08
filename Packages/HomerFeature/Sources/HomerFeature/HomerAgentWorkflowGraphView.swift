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

			HomerAgentWorkflowGraphContent(store: store)
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
		// Resizable, as a graph can be larger than any default size. A flexible frame alone leaves
		// the sheet's window fixed; `.fitted` sizing opens it at the ideal size and makes it
		// resizable down to the minimum (checked 2026-10-08).
		.frame(minWidth: 560, idealWidth: 820, maxWidth: .infinity, minHeight: 360, idealHeight: 680, maxHeight: .infinity)
		.presentationSizing(.fitted)
		.task { store.send(.task) }
	}
}

/// The graphs themselves, or why there are none — the sheet's body and the Workflow Graph section
/// of the agent's page. One graph takes all the space given and scrolls by itself; several
/// scroll together.
struct HomerAgentWorkflowGraphContent: View {
	let store: StoreOf<HomerAgentWorkflowGraphReducer>

	var body: some View {
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
			HomerWorkflowGraphView(
				topology: topology,
				maxHeight: maxHeight,
				imageName: "\(store.agentName) \(graph.label) workflow"
			) {
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
