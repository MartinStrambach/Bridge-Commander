import ComposableArchitecture
import SwiftUI

// MARK: - Label

/// The menu bar icon, with the number of terminal tabs waiting on the user beside it.
public struct MenuBarStatusLabel: View {
	private let store: StoreOf<RepositoryListReducer>

	@Environment(\.openWindow)
	private var openWindow

	/// The app icon's git graph, drawn as a template so the menu bar tints it. In the app target's
	/// asset catalog, hence the main bundle.
	private static let logo = Image("MenuBarLogo", bundle: .main).renderingMode(.template)

	/// Text sets an inline image on its baseline, which leaves the 16 pt glyph riding above the
	/// count; this centers it on the digits.
	private static let logoBaselineOffset: CGFloat = -3

	public init(model: RepositoryAppModel) {
		self.store = model.store
	}

	public var body: some View {
		let waitingCount = store.waitingSessions.count
		// One `Text` rather than an `HStack`: the status item renders a single image or text, and
		// drops the rest of a composed label.
		Group {
			if waitingCount > 0 {
				Text(Self.logo).baselineOffset(Self.logoBaselineOffset) + Text(" \(waitingCount)")
			}
			else {
				Self.logo
			}
		}
		.help(waitingCount > 0 ? "\(waitingCount) waiting for input" : "Bridge Commander")
		// The label is the one view of the app that is always on screen, so it is what opens the
		// main window when the reducer asks for it — from a clicked notification, say, after the
		// window was closed.
		.onChange(of: store.mainWindowRequestCount) {
			openWindow(id: RepositoryAppModel.mainWindowId)
		}
	}
}

// MARK: - Content

/// The menu bar extra's window: the tabs waiting on the user, and where each repository's branch
/// stands against its remote. A public wrapper, like `RootRepositoryView`: `@ViewAction` needs a
/// `store` as visible as the view, and the reducer is internal.
public struct MenuBarStatusView: View {
	private let model: RepositoryAppModel

	public init(model: RepositoryAppModel) {
		self.model = model
	}

	public var body: some View {
		MenuBarStatusContentView(store: model.store)
	}
}

@ViewAction(for: RepositoryListReducer.self)
struct MenuBarStatusContentView: View {
	let store: StoreOf<RepositoryListReducer>

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			header
			Divider()

			let waiting = store.menuBarWaitingSessions
			if !waiting.isEmpty {
				waitingSection(waiting)
				Divider()
			}

			repositoriesSection
			Divider()
			footer
		}
		.frame(width: 340)
		.onAppear { send(.menuBar(.appeared)) }
	}

	private var header: some View {
		HStack {
			Text("Bridge Commander")
				.font(.headline)
			Spacer()
			if store.isScanning {
				ProgressView()
					.controlSize(.small)
			}
			else {
				Button {
					send(.menuBar(.refreshButtonTapped))
				} label: {
					Image(systemName: "arrow.clockwise")
				}
				.buttonStyle(.borderless)
				.help("Refresh repository status")
			}
		}
		.padding(.horizontal, 12)
		.padding(.vertical, 10)
	}

	private func waitingSection(_ sessions: [MenuBarWaitingSession]) -> some View {
		VStack(alignment: .leading, spacing: 2) {
			Text(sessions.count == 1 ? "1 waiting for input" : "\(sessions.count) waiting for input")
				.font(.caption)
				.foregroundStyle(.secondary)
				.padding(.horizontal, 12)
				.padding(.bottom, 2)

			ForEach(sessions) { session in
				Button {
					send(.menuBar(.waitingSessionTapped(sessionId: session.id)))
				} label: {
					HStack(spacing: 8) {
						Circle()
							.fill(.orange)
							.frame(width: 7, height: 7)
						Text(session.location)
							.lineLimit(1)
							.truncationMode(.middle)
						Spacer()
						Image(systemName: "arrow.up.forward.app")
							.foregroundStyle(.secondary)
					}
					.contentShape(Rectangle())
					.padding(.horizontal, 12)
					.padding(.vertical, 4)
				}
				.buttonStyle(.plain)
				.help("Open this terminal tab")
			}
		}
		.padding(.vertical, 8)
	}

	@ViewBuilder
	private var repositoriesSection: some View {
		let repositories = store.menuBarRepositories
		if repositories.isEmpty {
			Text("No repositories")
				.foregroundStyle(.secondary)
				.frame(maxWidth: .infinity)
				.padding(.vertical, 16)
		}
		else {
			ScrollView {
				VStack(alignment: .leading, spacing: 0) {
					ForEach(repositories) { repository in
						MenuBarRepositoryRow(repository: repository)
					}
				}
				.padding(.vertical, 6)
			}
			// Sized to the rows up to a point, then scrolls.
			.frame(maxHeight: 420)
			.fixedSize(horizontal: false, vertical: repositories.count <= 12)
		}
	}

	private var footer: some View {
		HStack {
			Button("Open Bridge Commander") {
				send(.menuBar(.openWindowButtonTapped))
			}
			Spacer()
			Button("Quit") {
				send(.menuBar(.quitButtonTapped))
			}
		}
		.buttonStyle(.borderless)
		.padding(.horizontal, 12)
		.padding(.vertical, 10)
	}
}

// MARK: - Row

private struct MenuBarRepositoryRow: View {
	let repository: MenuBarRepositoryStatus

	var body: some View {
		HStack(spacing: 8) {
			Image(systemName: repository.isWorktree ? "arrow.triangle.branch" : "folder")
				.foregroundStyle(.secondary)
				.frame(width: 14)

			VStack(alignment: .leading, spacing: 0) {
				Text(repository.name)
					.lineLimit(1)
					.truncationMode(.middle)
				if let branchName = repository.branchName, branchName != repository.name {
					Text(branchName)
						.font(.caption)
						.foregroundStyle(.secondary)
						.lineLimit(1)
						.truncationMode(.middle)
				}
			}

			Spacer(minLength: 8)

			if repository.waitingSessionCount > 0 {
				Image(systemName: "bubble.left.fill")
					.foregroundStyle(.orange)
					.help("Waiting for input")
			}

			syncBadge
		}
		.padding(.leading, repository.isWorktree ? 26 : 12)
		.padding(.trailing, 12)
		.padding(.vertical, 3)
	}

	@ViewBuilder
	private var syncBadge: some View {
		switch repository.sync {
		case .unknown:
			Text("–")
				.foregroundStyle(.tertiary)
				.help("Status not loaded yet")
		case .unpublished:
			Image(systemName: "icloud.slash")
				.foregroundStyle(.secondary)
				.help("No upstream branch")
		case .upToDate:
			Image(systemName: "checkmark")
				.foregroundStyle(.green)
				.help("Up to date with its upstream")
		case let .diverged(ahead, behind):
			HStack(spacing: 6) {
				if ahead > 0 {
					Text("↑\(ahead)")
						.foregroundStyle(.orange)
						.help("\(ahead) to push")
				}
				if behind > 0 {
					Text("↓\(behind)")
						.foregroundStyle(.blue)
						.help("\(behind) to pull")
				}
			}
			.font(.callout.monospacedDigit())
		}
	}
}
