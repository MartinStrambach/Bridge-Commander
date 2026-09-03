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
		.background {
			focusSearchShortcut
			// ⌘A hands off to the terminal panel (select-all) while it's open, and is
			// meaningless with no repositories — matches the toggle's own visibility.
			if store.terminalLayout == nil, !store.repositoryGroups.isEmpty {
				toggleActiveTerminalsShortcut
			}
			// ⌘⇧§ reopens the terminal panel on an existing session — the counterpart
			// to ⌘§ inside TerminalLayoutView, which closes it.
			if store.terminalLayout == nil {
				showTerminalsShortcut
			}
		}
		.onAppear { send(.onAppear) }
		.onDisappear { send(.onDisappear) }
		// Returning to the app is when a permission granted in System Settings should take
		// effect. Nothing re-probes on refresh any more, so this is what clears the banners.
		.onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
			send(.didBecomeActive)
		}
		.onChange(of: store.periodicRefreshInterval) { _, _ in
			send(.periodicRefreshIntervalChanged)
		}
		.onChange(of: store.groupSettings) { _, _ in
			send(.groupSettingsChanged)
		}
		// The reducer can drop a session without going through the buttons that kill panes
		// directly, as it does when a worktree is deleted. Whatever the reason, a session that
		// has left the state must hang up its shell rather than run on unseen.
		.onChange(of: store.terminalSessions.ids) { _, ids in
			terminalViewStore.killSessions(notIn: Set(ids))
		}
		.alert($store.scope(\.$alert, action: \.alert))
	}

	@ViewBuilder
	private var repositoryContentView: some View {
		VStack(spacing: 0) {
			headerView
			Divider()
			if store.showPermissionDialog {
				permissionWarningBanner
			}
			if store.showAccessibilityPermissionDialog {
				accessibilityPermissionWarningBanner
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
		if let terminalLayoutStore = store.scope(\.terminalLayout, action: \.terminalLayout) {
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
			// Title and the list filter read as one unit, set apart from the action buttons.
			HStack(spacing: 12) {
				Text("Bridge Commander")
					.font(.title2)
					.fontWeight(.bold)

				if !store.repositoryGroups.isEmpty {
					// Bound manually rather than with @Bindable: the flag is fileprivate(set) and
					// all mutation goes through the reducer, same as the search field below.
					Toggle(
						"Active terminals",
						isOn: Binding(
							get: { store.showsActiveTerminalsOnly },
							set: { send(.activeTerminalFilterChanged($0)) }
						)
					)
					.toggleStyle(.switch)
					.controlSize(.small)
					.padding(.horizontal, 10)
					.padding(.vertical, 6)
					// Opaque rather than a `.secondary.opacity(…)` tint, so the chip reads as one
					// solid control against the window background.
					.background(
						Color(nsColor: .controlBackgroundColor),
						in: RoundedRectangle(cornerRadius: 6)
					)
					.help("Show only repositories with an open terminal (⌘A)")
				}
			}

			HeaderButton(
				icon: "terminal",
				tooltip: "Open terminal in home directory (⌘T)",
				action: { send(.openHomeTerminalButtonTapped) }
			)
			// Only own ⌘T while the terminal panel is closed. When it's open, the
			// new-tab button in TerminalPanelView claims ⌘T instead. Both views stay
			// in the hierarchy (this one is just opacity-0), and an invisible view
			// keeps its keyboard shortcut — so without this gate both would register
			// ⌘T and SwiftUI would dispatch to either one non-deterministically.
			.commandShortcut("t", enabled: store.terminalLayout == nil)

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
						// Same handoff as ⌘T above: while the terminal panel is open,
						// ⌘R belongs to TerminalLayoutView and refreshes only the opened repo.
						.commandShortcut("r", enabled: store.terminalLayout == nil)
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

	private var accessibilityPermissionWarningBanner: some View {
		BannerView(
			icon: "exclamationmark.triangle.fill",
			title: "Accessibility permission required",
			subtitle: "Opening terminal tabs requires accessibility access.",
			actionLabel: "Open System Settings",
			onAction: { send(.openAccessibilitySettingsButtonTapped) },
			onDismiss: { send(.dismissAccessibilityPermissionWarningButtonTapped) }
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

	private var toggleActiveTerminalsShortcut: some View {
		Button("") { send(.activeTerminalFilterChanged(!store.showsActiveTerminalsOnly)) }
			.keyboardShortcut("a", modifiers: .command)
			.hidden()
	}

	private var showTerminalsShortcut: some View {
		Button("") { send(.showTerminalsRequested) }
			.keyboardShortcut("§", modifiers: [.command, .shift])
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

	@ViewBuilder
	private var repositoryListView: some View {
		// Build a path → status map once so each row does an O(1) lookup instead of
		// scanning the whole sessions array.
		let statusByPath = Dictionary(
			store.terminalSessions.map { ($0.repositoryPath, $0.status) },
			uniquingKeysWith: { first, _ in first }
		)
		// Only sessions with a usable terminal count; `.failed` ones linger in state but show no
		// dot. Built from the sessions array rather than `statusByPath` so a repo whose first tab
		// died but whose second is alive still counts as active.
		let livePaths: Set<String>? = store.showsActiveTerminalsOnly
			? Set(store.terminalSessions.filter(\.status.isLive).map(\.repositoryPath))
			: nil

		// Checked per group rather than as `livePaths.isEmpty` so a live session that maps to no
		// row (e.g. the home-directory terminal) still counts as "nothing to show".
		if let livePaths,
			store.repositoryGroups.allSatisfy({
				$0.rowVisibility(query: store.searchText, livePaths: livePaths).isHidden
			})
		{
			EmptyStateView(
				title: "No Active Terminals",
				systemImage: "terminal",
				description: "Open a terminal in a repository, or turn off the Active terminals filter."
			)
		}
		else {
			// Scope into the stored groups, not a filtered copy of them: each group resolves the filters
			// against its own rows (see RowVisibility), so a keystroke neither rebuilds group state nor
			// re-filters the whole list once per child-store read.
			List {
				ForEach(store.scope(\.repositoryGroups, action: \.repositoryGroups)) { groupStore in
					RepoGroupView(
						store: groupStore,
						statusByPath: statusByPath,
						searchText: store.searchText,
						livePaths: livePaths,
						sortMode: store.sortMode
					)
				}
			}
			.listStyle(.plain)
			.onDrop(of: [UTType.folder], isTargeted: nil, perform: handleDrop)
		}
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

private extension View {
	/// Applies a ⌘-modified keyboard shortcut only when `enabled`. Used to hand
	/// shortcuts off to the terminal panel while it's open, since an opacity-0
	/// view in the hierarchy would otherwise keep claiming the shortcut.
	@ViewBuilder
	func commandShortcut(_ key: KeyEquivalent, enabled: Bool) -> some View {
		if enabled {
			keyboardShortcut(key, modifiers: .command)
		}
		else {
			self
		}
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
