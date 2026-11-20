import ComposableArchitecture
import Foundation

@Reducer
public struct DependencyGraphReducer {
	@ObservableState
	public struct State: Equatable, Identifiable {
		public let repositoryPath: String
		let repositoryName: String
		let iosSubfolderPath: String
		/// The group's default branch setting; empty resolves it from the remote.
		let configuredDefaultBranch: String

		@Shared(.dependencyGraphPlatform)
		var platform = ModulePlatform.kmp
		@Shared(.dependencyGraphHighlightsChanges)
		var highlightsChanges = true
		@Shared(.dependencyGraphShowsOtherPlatforms)
		var showsOtherPlatforms = true
		@Shared(.dependencyGraphIncludesTestDependencies)
		var includesTestDependencies = false
		/// Draws the edges a longer path already implies (`PlatformGraph.indirectEdges`).
		/// Drawing only, so it needs no rebuild.
		@Shared(.dependencyGraphShowsIndirectEdges)
		var showsIndirectEdges = false

		var graph: DependencyGraph?
		var isLoading = false
		var changes: ModuleChanges?
		var changesError: String?
		var isLoadingChanges = false

		/// What the canvas draws, rebuilt (`rebuild`) whenever the graph or a view option changes.
		var platformGraph = PlatformGraph.empty
		var layout = GraphLayout.empty
		/// Bumped on every rebuild, so the canvas fits the new layout to the view.
		var layoutRevision = 0

		var selectedModuleID: String?
		var searchText = ""

		public var id: String { repositoryPath }

		public init(
			repositoryPath: String,
			repositoryName: String,
			iosSubfolderPath: String,
			configuredDefaultBranch: String
		) {
			self.repositoryPath = repositoryPath
			self.repositoryName = repositoryName
			self.iosSubfolderPath = iosSubfolderPath
			self.configuredDefaultBranch = configuredDefaultBranch
		}

		/// The remembered platform, or the first one the repository has when it lacks that one.
		var effectivePlatform: ModulePlatform {
			let available = graph?.platforms ?? []
			return available.contains(platform) ? platform : available.first ?? platform
		}

		/// Changes to draw: nil while highlighting is off.
		var visibleChanges: ModuleChanges? {
			highlightsChanges ? changes : nil
		}

		/// The current platform's modules matching the search, by title.
		var listedModules: [DependencyModule] {
			let query = searchText.trimmingCharacters(in: .whitespaces)
			let modules = platformGraph.modules.filter { !platformGraph.boundaryModuleIDs.contains($0.id) }
			let matching = query.isEmpty
				? modules
				: modules.filter { $0.name.localizedCaseInsensitiveContains(query) }
			return matching.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
		}

		/// The listed modules the branch added or changed, new ones first.
		var listedChangedModules: [DependencyModule] {
			guard let changes = visibleChanges else {
				return []
			}
			return listedModules
				.filter { changes.status(of: $0.id) != nil }
				.sorted { (changes.status(of: $0.id) == .new ? 0 : 1) < (changes.status(of: $1.id) == .new ? 0 : 1) }
		}
	}

	public enum Action: BindableAction {
		case binding(BindingAction<State>)
		case task
		case refreshButtonTapped
		case graphLoaded(Result<DependencyGraph, any Error>)
		case changesLoaded(Result<ModuleChanges, any Error>)
		case platformSelected(ModulePlatform)
		case highlightsChangesToggled(Bool)
		case showsOtherPlatformsToggled(Bool)
		case includesTestDependenciesToggled(Bool)
		case showsIndirectEdgesToggled(Bool)
		/// A module picked on the canvas or in a list; nil clears the selection.
		case moduleSelected(String?)
		case closeButtonTapped
	}

	private enum CancelID {
		case graph
		case changes
	}

	@Dependency(DependencyGraphClient.self)
	private var client
	@Dependency(\.dismiss)
	private var dismiss

	public init() {}

	public var body: some Reducer<State, Action> {
		BindingReducer()

		Reduce { state, action in
			switch action {
			case .binding:
				return .none

			case .task:
				guard state.graph == nil, !state.isLoading else {
					return .none
				}
				return loadGraph(state: &state)

			case .refreshButtonTapped:
				return loadGraph(state: &state)

			case let .graphLoaded(.success(graph)):
				state.isLoading = false
				state.graph = graph
				rebuild(&state)
				return state.highlightsChanges ? loadChanges(state: &state) : .none

			case .graphLoaded(.failure):
				// The loader reads what it can and does not throw today; an empty graph shows the
				// empty state.
				state.isLoading = false
				state.graph = DependencyGraph(modules: [], edges: [])
				rebuild(&state)
				return .none

			case let .changesLoaded(.success(changes)):
				state.isLoadingChanges = false
				state.changes = changes
				state.changesError = nil
				return .none

			case let .changesLoaded(.failure(error)):
				state.isLoadingChanges = false
				state.changes = nil
				state.changesError = error.localizedDescription
				return .none

			case let .platformSelected(platform):
				state.$platform.withLock { $0 = platform }
				rebuild(&state)
				return .none

			case let .highlightsChangesToggled(isOn):
				state.$highlightsChanges.withLock { $0 = isOn }
				// While the graph reloads, its answer loads the changes against the new modules.
				guard isOn, state.changes == nil, state.graph != nil, !state.isLoading, !state.isLoadingChanges else {
					return .none
				}
				return loadChanges(state: &state)

			case let .showsOtherPlatformsToggled(isOn):
				state.$showsOtherPlatforms.withLock { $0 = isOn }
				rebuild(&state)
				return .none

			case let .includesTestDependenciesToggled(isOn):
				state.$includesTestDependencies.withLock { $0 = isOn }
				rebuild(&state)
				return .none

			case let .showsIndirectEdgesToggled(isOn):
				state.$showsIndirectEdges.withLock { $0 = isOn }
				return .none

			case let .moduleSelected(id):
				state.selectedModuleID = id
				return .none

			case .closeButtonTapped:
				return .run { [dismiss] _ in await dismiss() }
			}
		}
	}

	/// Every load of the graph goes through here, under one cancel id; a reload drops the
	/// branch changes too, which are classified against the graph's modules.
	private func loadGraph(state: inout State) -> Effect<Action> {
		state.isLoading = true
		state.changes = nil
		state.changesError = nil
		state.isLoadingChanges = false
		return .merge(
			.cancel(id: CancelID.changes),
			.run { [client, repositoryPath = state.repositoryPath, iosSubfolderPath = state.iosSubfolderPath] send in
				await send(.graphLoaded(Result {
					try await client.loadGraph(repositoryPath, iosSubfolderPath)
				}))
			}
			.cancellable(id: CancelID.graph, cancelInFlight: true)
		)
	}

	private func loadChanges(state: inout State) -> Effect<Action> {
		guard let graph = state.graph, !graph.modules.isEmpty else {
			return .none
		}

		state.isLoadingChanges = true
		return .run { [
			client,
			repositoryPath = state.repositoryPath,
			configuredDefaultBranch = state.configuredDefaultBranch,
			modules = graph.modules
		] send in
			await send(.changesLoaded(Result {
				try await client.loadChanges(repositoryPath, configuredDefaultBranch, modules)
			}))
		}
		.cancellable(id: CancelID.changes, cancelInFlight: true)
	}

	/// Recomputes the drawn subgraph and its layout, and drops a selection it no longer holds.
	private func rebuild(_ state: inout State) {
		guard let graph = state.graph else {
			return
		}

		state.platformGraph = PlatformGraph.make(
			from: graph,
			platform: state.effectivePlatform,
			includesOtherPlatforms: state.showsOtherPlatforms,
			includesTestDependencies: state.includesTestDependencies
		)
		let widths = Dictionary(
			state.platformGraph.modules.map { ($0.id, LayeredGraphLayout.nodeWidth(title: $0.title, subtitle: $0.subtitle)) },
			uniquingKeysWith: { first, _ in first }
		)
		let essential = state.platformGraph.edges
			.filter { !state.platformGraph.indirectEdges.contains($0) }
			.reduce(into: [String: [String]]()) { $0[$1.from, default: []].append($1.to) }
		state.layout = LayeredGraphLayout.layout(
			ids: state.platformGraph.modules.map(\.id),
			widths: widths,
			dependencies: state.platformGraph.dependencies,
			essentialDependencies: essential,
			boundaryIDs: state.platformGraph.boundaryModuleIDs
		)
		state.layoutRevision += 1
		if let selected = state.selectedModuleID, state.platformGraph.module(withID: selected) == nil {
			state.selectedModuleID = nil
		}
	}
}
