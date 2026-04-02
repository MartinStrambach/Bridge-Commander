import ComposableArchitecture
import SwiftUI
import UniformTypeIdentifiers
import AppUI
import Settings
import TerminalFeature

// MARK: - Public entry point

/// Public wrapper that self-initialises the store. Used by BridgeCommanderApp.
public struct RootRepositoryView: View {
	private let store: StoreOf<RepositoryListReducer>

	public init() {
		self.store = Store(
			initialState: RepositoryListReducer.State(),
			reducer: { RepositoryListReducer() }
		)
	}

	public var body: some View {
		RepositoryListView(store: store)
	}
}

// MARK: - Internal view

@ViewAction(for: RepositoryListReducer.self)
struct RepositoryListView: View {
	@Bindable
	var store: StoreOf<RepositoryListReducer>

	@State
	private var terminalViewStore = TerminalViewStore()
	@FocusState
	private var isSearchFocused: Bool

	private var sortModeIcon: String {
		switch store.sortMode {
		case .state:
			"chart.bar.fill"
		case .ticket:
			"ticket.fill"
		case .branch:
			"line.horizontal.3"
		}
	}

	private var sortModeTooltip: String {
		switch store.sortMode {
		case .state:
			"Sorted by state (click to sort by ticket)"
		case .ticket:
			"Sorted by ticket (click to sort by branch)"
		case .branch:
			"Sorted by branch (click to sort by state)"
		}
	}

	var body: some View {
		ZStack {
			// Repository list — always in hierarchy so there's no cold-start layout cost
			// when the terminal panel is hidden. Fades out while the terminal is visible.
			repositoryContentView
				.opacity(store.terminalLayout != nil ? 0 : 1)

			// Terminal overlay — fades in/out on top with opacity only.
			// Avoids per-frame NSView frame repositioning that .move would cause on
			// the Metal-backed SwiftTerm views inside TerminalContainerRepresentable.
			terminalOverlayView
		}
		.windowMinSize(width: store.terminalLayout != nil ? 800 : 600, height: 400)
		.animation(.spring(duration: 0.3), value: store.terminalLayout != nil)
		.background { focusSearchShortcut }
		.onAppear { send(.onAppear) }
		.onDisappear { send(.onDisappear) }
		.onChange(of: store.periodicRefreshInterval) { _, _ in
			send(.periodicRefreshIntervalChanged)
		}
		.onChange(of: store.groupSettings) { _, _ in
			send(.groupSettingsChanged)
		}
		.alert($store.scope(state: \.$alert, action: \.alert))
	}

	@ViewBuilder
	private var repositoryContentView: some View {
		VStack(spacing: 0) {
			headerView
			Divider()
			if store.showPermissionDialog {
				permissionWarningBanner
			}
			if store.repositoryGroups.isEmpty {
				emptyStateView
			}
			else {
				searchBarView
				Divider()
				repositoryListView
			}
		}
	}

	@ViewBuilder
	private var terminalOverlayView: some View {
		if let terminalLayoutStore = store.scope(state: \.terminalLayout, action: \.terminalLayout) {
			TerminalLayoutView(
				store: terminalLayoutStore,
				repositoryGroups: store.repositoryGroups,
				sessions: store.terminalSessions,
				terminalViewStore: terminalViewStore,
				onStatusChange: { sessionId, status in
					MainActor.assumeIsolated {
						_ = store.send(.terminalLayout(.sessionStatusChanged(sessionId: sessionId, status: status)))
					}
				}
			)
			.transition(.opacity)
		}
	}

	// MARK: - Header View

	private var headerView: some View {
		HStack {
			VStack(alignment: .leading, spacing: 4) {
				Text("Bridge Commander")
					.font(.title2)
					.fontWeight(.bold)
			}
			if !store.repositoryGroups.isEmpty {
				HStack(spacing: 8) {
					HeaderButton(
						icon: sortModeIcon,
						tooltip: sortModeTooltip,
						action: { send(.sortModeButtonTapped) }
					)

					Spacer()

					HStack(spacing: 12) {
						let repoCount = store.repositoryGroups.count
						Text("\(repoCount) \(repoCount == 1 ? "repository" : "repositories")")
							.font(.subheadline)
							.foregroundColor(.secondary)

						HeaderButton(
							icon: "arrow.clockwise",
							tooltip: "Refresh repository status (⌘R)",
							color: .blue,
							action: { send(.refreshButtonTapped) }
						)
						.keyboardShortcut("r", modifiers: .command)
						.opacity(store.isScanning ? 0 : 1)
						.overlay {
							if store.isScanning {
								ProgressView()
									.scaleEffect(0.55)
							}
						}
						.disabled(store.isScanning)

						HeaderButton(
							icon: "plus",
							tooltip: "Add repository",
							action: addRepository
						)

						HeaderButton(
							icon: "xmark.circle.fill",
							tooltip: "Clear results",
							action: { send(.clearButtonTapped) }
						)
					}
				}
			}
			else {
				Spacer()
			}
		}
		.padding()
	}

	// MARK: - Permission Warning Banner

	private var permissionWarningBanner: some View {
		BannerView(
			icon: "exclamationmark.triangle.fill",
			title: "Automation permission required",
			subtitle: "Some features may not work correctly.",
			actionLabel: "Open System Settings",
			onAction: { send(.openAutomationSettingsButtonTapped) },
			onDismiss: { send(.dismissPermissionWarningButtonTapped) }
		)
	}

	// MARK: - Empty State View

	private var emptyStateView: some View {
		VStack(spacing: 20) {
			Image(systemName: "folder.badge.gearshape")
				.font(.system(size: 64))
				.foregroundColor(.secondary)

			VStack(spacing: 8) {
				Text("No Repositories Found")
					.font(.title3)
					.fontWeight(.semibold)

				Text("Add a Git repository to get started")
					.font(.body)
					.foregroundColor(.secondary)
					.multilineTextAlignment(.center)
			}

			Button(action: addRepository) {
				Label("Add Repository", systemImage: "folder.badge.plus")
					.padding(.horizontal, 8)
			}
			.buttonStyle(.borderedProminent)
			.controlSize(.large)
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.padding()
		.background(Color(.controlBackgroundColor))
	}

	// MARK: - Search Bar

	private var focusSearchShortcut: some View {
		Button("") { isSearchFocused = true }
			.keyboardShortcut("f", modifiers: .command)
			.hidden()
	}

	private var searchBarView: some View {
		HStack(spacing: 6) {
			Image(systemName: "magnifyingglass")
				.foregroundStyle(.secondary)
			TextField(
				"Filter by branch name…",
				text: Binding(get: { store.searchText }, set: { send(.searchTextChanged($0)) })
			)
			.textFieldStyle(.plain)
			.focused($isSearchFocused)
			if !store.searchText.isEmpty {
				Button {
					send(.searchTextChanged(""))
				} label: {
					Image(systemName: "xmark.circle.fill")
						.foregroundStyle(.secondary)
						.contentShape(Rectangle())
				}
				.buttonStyle(.plain)
			}
		}
		.padding(.horizontal, 12)
		.padding(.vertical, 7)
	}

	// MARK: - Repository List View

	private var repositoryListView: some View {
		List {
			ForEach(store.scope(state: \.filteredRepositoryGroups, action: \.repositoryGroups)) { groupStore in
				RepoGroupView(
					store: groupStore,
					sessions: store.terminalSessions
				)
			}
		}
		.listStyle(.plain)
		.onDrop(of: [UTType.folder], isTargeted: nil, perform: handleDrop)
	}

	// MARK: - Repository Selection

	private func addRepository() {
		let panel = NSOpenPanel()
		panel.canChooseFiles = false
		panel.canChooseDirectories = true
		panel.allowsMultipleSelection = false
		panel.message = "Select a Git repository"

		if panel.runModal() == .OK, let url = panel.url {
			send(.addRepository(url.path))
		}
	}

	// MARK: - Drag & Drop

	@discardableResult
	private func handleDrop(providers: [NSItemProvider]) -> Bool {
		for provider in providers {
			_ = provider.loadObject(ofClass: URL.self) { url, _ in
				if let url {
					Task { @MainActor in
						send(.addRepository(url.path))
					}
				}
			}
		}
		return true
	}

}

#Preview {
	RepositoryListView(
		store: Store(
			initialState: RepositoryListReducer.State(),
			reducer: {
				RepositoryListReducer()
			}
		)
	)
}
