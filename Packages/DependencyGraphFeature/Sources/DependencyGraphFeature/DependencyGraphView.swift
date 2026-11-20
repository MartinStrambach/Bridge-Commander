import AppUI
import ComposableArchitecture
import SwiftUI

public struct DependencyGraphView: View {
	@Bindable var store: StoreOf<DependencyGraphReducer>

	public init(store: StoreOf<DependencyGraphReducer>) {
		self.store = store
	}

	public var body: some View {
		VStack(spacing: 0) {
			header
			Divider()
			content
			Divider()
			statusBar
		}
		.task {
			store.send(.task)
		}
	}

	// MARK: - Header

	private var header: some View {
		HStack(spacing: 12) {
			Text("Module Dependencies")
				.scaledFont(.title2)
				.fontWeight(.semibold)

			Text(store.repositoryName)
				.scaledFont(.title3)
				.foregroundStyle(.secondary)
				.lineLimit(1)

			Spacer()

			if let platforms = store.graph?.platforms, !platforms.isEmpty {
				Picker(
					"Platform",
					selection: Binding(get: { store.effectivePlatform }, set: { store.send(.platformSelected($0)) })
				) {
					ForEach(platforms) { platform in
						Text(platform.title).tag(platform)
					}
				}
				.pickerStyle(.segmented)
				.labelsHidden()
				.fixedSize()
			}

			Toggle(
				"Highlight changes",
				isOn: Binding(get: { store.highlightsChanges }, set: { store.send(.highlightsChangesToggled($0)) })
			)
			.help("Mark modules this branch added or changed since it left the default branch")

			Toggle(
				"Other platforms",
				isOn: Binding(get: { store.showsOtherPlatforms }, set: { store.send(.showsOtherPlatformsToggled($0)) })
			)
			.help("Show the other platforms' modules this platform's modules depend on, dimmed")

			Toggle(
				"Test dependencies",
				isOn: Binding(
					get: { store.includesTestDependencies },
					set: { store.send(.includesTestDependenciesToggled($0)) }
				)
			)
			.help("Include dependencies declared only for tests")

			Toggle(
				"Indirect edges",
				isOn: Binding(get: { store.showsIndirectEdges }, set: { store.send(.showsIndirectEdgesToggled($0)) })
			)
			.help("Also draw the edges a longer path already implies (a → c when a → b → c). A selected module always shows all of its own")

			Button {
				store.send(.refreshButtonTapped)
			} label: {
				Image(systemName: "arrow.clockwise")
					.opacity(store.isLoading ? 0 : 1)
					.overlay {
						if store.isLoading {
							ProgressView()
								.scaleEffect(0.4)
						}
					}
			}
			.keyboardShortcut("r", modifiers: .command)
			.help(store.isLoading ? "Reading build files…" : "Reread the build files and branch changes (⌘R)")
			.disabled(store.isLoading)

			Button("Close") {
				store.send(.closeButtonTapped)
			}
			.buttonStyle(.scaledAutomatic)
			.keyboardShortcut(.cancelAction)
		}
		.toggleStyle(.checkbox)
		.scaledFont(.callout)
		.padding()
		.background(Color(nsColor: .windowBackgroundColor))
	}

	// MARK: - Content

	@ViewBuilder
	private var content: some View {
		if let graph = store.graph {
			if graph.modules.isEmpty {
				EmptyStateView(
					title: "No Modules Found",
					systemImage: "point.3.connected.trianglepath.dotted",
					description: "Bridge Commander reads Gradle modules from settings.gradle.kts and iOS frameworks from "
						+ "Tuist/ProjectDescriptionHelpers. This repository has neither."
				)
			}
			else {
				HSplitView {
					sidebar
						.frame(minWidth: 240, idealWidth: 300, maxWidth: 420)
					DependencyGraphCanvas(
						graph: store.platformGraph,
						layout: store.layout,
						layoutRevision: store.layoutRevision,
						changes: store.visibleChanges,
						selectedID: store.selectedModuleID,
						showsIndirectEdges: store.showsIndirectEdges,
						onSelect: { store.send(.moduleSelected($0)) }
					)
					.frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
				}
			}
		}
		else {
			ProgressView("Reading build files…")
				.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
	}

	// MARK: - Sidebar

	private var sidebar: some View {
		VSplitView {
			VStack(spacing: 0) {
				TextField("Filter modules", text: $store.searchText)
					.textFieldStyle(.roundedBorder)
					.scaledFont(.body)
					.padding(8)
				moduleList
			}
			.frame(minHeight: 200)

			if let selectedID = store.selectedModuleID, let module = store.platformGraph.module(withID: selectedID) {
				ModuleInspector(
					module: module,
					graph: store.platformGraph,
					changes: store.visibleChanges,
					onSelect: { store.send(.moduleSelected($0)) }
				)
				.frame(minHeight: 160, idealHeight: 280)
			}
		}
	}

	private var moduleList: some View {
		let changed = store.listedChangedModules
		let changedIDs = Set(changed.map(\.id))
		let others = store.listedModules.filter { !changedIDs.contains($0.id) }
		return List(selection: Binding(get: { store.selectedModuleID }, set: { store.send(.moduleSelected($0)) })) {
			if !changed.isEmpty {
				Section {
					ForEach(changed) { module in
						ModuleListRow(module: module, changes: store.visibleChanges)
							.tag(module.id)
					}
				} header: {
					Text("New and changed on this branch (\(changed.count))")
				}
			}
			Section {
				ForEach(others) { module in
					ModuleListRow(module: module, changes: store.visibleChanges)
						.tag(module.id)
				}
			} header: {
				Text(changed.isEmpty ? "Modules (\(others.count))" : "Other modules (\(others.count))")
			}
		}
		.listStyle(.sidebar)
	}

	// MARK: - Status Bar

	private var statusBar: some View {
		HStack(spacing: 14) {
			legendItem(color: GraphPalette.dependency, title: "Depends on")
			legendItem(color: GraphPalette.dependent, title: "Used by")
			if store.highlightsChanges {
				legendItem(color: GraphPalette.color(for: .new), title: "New (\(store.changes?.newModules.count ?? 0))")
				legendItem(
					color: GraphPalette.color(for: .changed),
					title: "Changed (\(store.changes?.changedModules.count ?? 0))"
				)
			}

			Spacer()

			if store.highlightsChanges {
				changesSummary
			}
		}
		.scaledFont(.caption)
		.foregroundStyle(.secondary)
		.padding(.horizontal)
		.padding(.vertical, 6)
		.background(Color(nsColor: .windowBackgroundColor))
	}

	@ViewBuilder
	private var changesSummary: some View {
		if store.isLoadingChanges {
			ProgressView()
				.controlSize(.small)
			Text("Finding the branch's changes…")
		}
		else if let error = store.changesError {
			Image(systemName: "exclamationmark.triangle.fill")
				.foregroundStyle(.orange)
			Text("Changes unavailable: \(error)")
				.lineLimit(1)
				.truncationMode(.middle)
				.help(error)
		}
		else if let changes = store.changes {
			Text("Compared with \(changes.baseRef) at \(changes.mergeBase.prefix(9)), uncommitted changes included")
				.lineLimit(1)
				.truncationMode(.middle)
		}
	}

	private func legendItem(color: Color, title: String) -> some View {
		HStack(spacing: 4) {
			RoundedRectangle(cornerRadius: 2)
				.fill(color)
				.frame(width: 10, height: 10)
			Text(title)
		}
	}
}

// MARK: - Module List Row

struct ModuleListRow: View {
	let module: DependencyModule
	let changes: ModuleChanges?

	var body: some View {
		HStack(spacing: 8) {
			RoundedRectangle(cornerRadius: 2)
				.fill(GraphPalette.color(for: module.kind))
				.frame(width: 4)
			VStack(alignment: .leading, spacing: 1) {
				Text(module.title)
					.scaledFont(.callout)
					.lineLimit(1)
				Text(module.subtitle)
					.scaledFont(.caption2)
					.foregroundStyle(.secondary)
					.lineLimit(1)
					.truncationMode(.middle)
			}
			Spacer(minLength: 0)
			if let status = changes?.status(of: module.id) {
				Text(status == .new ? "New" : "\(changes?.changedFileCounts[module.id] ?? 0)")
					.scaledFont(.caption2)
					.fontWeight(.semibold)
					.monospacedDigit()
					.padding(.horizontal, 5)
					.padding(.vertical, 1)
					.background(GraphPalette.color(for: status).opacity(0.25), in: Capsule())
					.help(status == .new ? "Added on this branch" : "Files changed on this branch")
			}
		}
		.help(module.name)
	}
}

// MARK: - Module Inspector

/// The selected module: where it lives and its direct dependencies and dependents, each a link
/// that selects it.
struct ModuleInspector: View {
	let module: DependencyModule
	let graph: PlatformGraph
	let changes: ModuleChanges?
	let onSelect: (String) -> Void

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 10) {
				VStack(alignment: .leading, spacing: 2) {
					Text(module.name)
						.scaledFont(.headline)
						.textSelection(.enabled)
					Text(module.kind.title)
						.scaledFont(.caption)
						.foregroundStyle(.secondary)
					ForEach(module.directories, id: \.self) { directory in
						Text(directory)
							.scaledFont(.caption)
							.foregroundStyle(.secondary)
							.textSelection(.enabled)
					}
					if let status = changes?.status(of: module.id) {
						Text(statusText(status))
							.scaledFont(.caption)
							.foregroundStyle(GraphPalette.color(for: status))
					}
				}

				moduleLinks(
					title: "Depends on",
					ids: graph.dependencies[module.id] ?? [],
					transitiveCount: graph.transitiveDependencies(of: module.id).count
				)
				moduleLinks(
					title: "Used by",
					ids: graph.dependents[module.id] ?? [],
					transitiveCount: graph.transitiveDependents(of: module.id).count
				)
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding(10)
		}
	}

	private func statusText(_ status: ModuleChanges.Status) -> String {
		let count = changes?.changedFileCounts[module.id] ?? 0
		let files = count == 1 ? "1 file" : "\(count) files"
		return status == .new ? "New on this branch (\(files))" : "Changed on this branch (\(files))"
	}

	@ViewBuilder
	private func moduleLinks(title: String, ids: [String], transitiveCount: Int) -> some View {
		VStack(alignment: .leading, spacing: 3) {
			Text("\(title) \(ids.count) directly, \(transitiveCount) in all")
				.scaledFont(.caption)
				.fontWeight(.semibold)
				.foregroundStyle(.secondary)
			ForEach(ids.sorted(), id: \.self) { id in
				Button {
					onSelect(id)
				} label: {
					Text(graph.module(withID: id)?.name ?? id)
						.scaledFont(.caption)
						.lineLimit(1)
						.truncationMode(.middle)
				}
				.buttonStyle(.link)
			}
		}
	}
}

// MARK: - Sheet Frame

public extension View {
	/// The size the sheet opens at, shared by every presenter: wide enough for the sidebar and a
	/// readable stretch of graph.
	func dependencyGraphSheetFrame() -> some View {
		frame(
			minWidth: 1000,
			idealWidth: 1500,
			maxWidth: .infinity,
			minHeight: 650,
			idealHeight: 950,
			maxHeight: .infinity
		)
		.windowResizable()
	}
}
