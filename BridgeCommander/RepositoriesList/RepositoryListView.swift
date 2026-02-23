import ComposableArchitecture
import SwiftUI

@ViewAction(for: RepositoryListReducer.self)
struct RepositoryListView: View {
	let store: StoreOf<RepositoryListReducer>

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
		VStack(spacing: 0) {
			// Header
			headerView

			Divider()

			if store.showPermissionDialog {
				permissionWarningBanner
			}

			if store.repositories.isEmpty {
				emptyStateView
			}
			else {
				repositoryListView
			}
		}
		.frame(minWidth: 600, minHeight: 400)
		.onAppear {
			send(.onAppear)
		}
		.onDisappear {
			send(.onDisappear)
		}
		.onChange(of: store.periodicRefreshInterval) { _, _ in
			send(.periodicRefreshIntervalChanged)
		}
	}

	// MARK: - Header View

	private var headerView: some View {
		HStack {
			VStack(alignment: .leading, spacing: 4) {
				Text("Bridge Commander")
					.font(.title2)
					.fontWeight(.bold)

				if let directory = store.selectedDirectory {
					Text(directory)
						.font(.caption)
						.foregroundColor(.secondary)
						.lineLimit(1)
						.truncationMode(.middle)
				}
				else {
					Text("No directory selected")
						.font(.caption)
						.foregroundColor(.secondary)
				}
			}
			if !store.repositories.isEmpty {
				HStack(spacing: 8) {
					HeaderButton(
						icon: sortModeIcon,
						tooltip: sortModeTooltip,
						action: { send(.sortModeButtonTapped) }
					)

					Spacer()

					HStack(spacing: 12) {
						Text("\(store.repositories.count) repositories")
							.font(.subheadline)
							.foregroundColor(.secondary)

						if store.isScanning {
							ProgressView()
								.scaleEffect(0.7)
						}
						else {
							HeaderButton(
								icon: "arrow.clockwise",
								tooltip: "Refresh repository status (⌘R)",
								color: .blue,
								action: { send(.refreshButtonTapped) }
							)
							.keyboardShortcut("r", modifiers: .command)
						}

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

	// MARK: - Scanning View

	private var scanningView: some View {
		VStack(spacing: 16) {
			ProgressView()
			Text("Scanning repositories...")
				.font(.headline)
				.foregroundColor(.secondary)
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.background(Color(.controlBackgroundColor))
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

				Text("Select a directory to scan for Git repositories and worktrees")
					.font(.body)
					.foregroundColor(.secondary)
					.multilineTextAlignment(.center)
			}

			Button(action: selectDirectory) {
				Label("Select Directory", systemImage: "folder")
					.padding(.horizontal, 8)
			}
			.buttonStyle(.borderedProminent)
			.controlSize(.large)
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.padding()
		.background(Color(.controlBackgroundColor))
	}

	// MARK: - Repository List View

	private var repositoryListView: some View {
		List(store.scope(state: \.repositories, action: \.repositories)) { rowStore in
			RepositoryRowView(store: rowStore)
		}
		.listStyle(.plain)
	}

	// MARK: - Directory Selection

	private func selectDirectory() {
		let panel = NSOpenPanel()
		panel.canChooseFiles = false
		panel.canChooseDirectories = true
		panel.allowsMultipleSelection = false
		panel.message = "Select a directory to scan for repositories"

		if panel.runModal() == .OK, let url = panel.url {
			send(.directorySelected(url.path))
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
