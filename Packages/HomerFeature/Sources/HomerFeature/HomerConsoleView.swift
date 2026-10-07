import AppUI
import ComposableArchitecture
import SwiftUI

/// The Homer section of the main window. `sectionSwitcher` heads it, in the place it holds in
/// every section's header.
public struct HomerConsoleView: View {
	@Bindable
	private var store: StoreOf<HomerConsoleReducer>
	private let sectionSwitcher: AppSectionSwitcher

	public init(store: StoreOf<HomerConsoleReducer>, sectionSwitcher: AppSectionSwitcher) {
		self.store = store
		self.sectionSwitcher = sectionSwitcher
	}

	public var body: some View {
		VStack(spacing: 0) {
			headerView
			Divider()
			content
		}
		.onAppear { store.send(.appeared) }
		.onDisappear { store.send(.disappeared) }
		.sheet(item: $store.webPage) { page in
			HomerWebPageView(page: page)
		}
	}

	private var showsConsole: Bool {
		store.user != nil && !store.isChangingInstance
	}

	@ViewBuilder
	private var content: some View {
		switch store.session {
		case .checking:
			ProgressView("Connecting to \(HomerEndpoint.displayName(of: store.baseURL))…")
				.frame(maxWidth: .infinity, maxHeight: .infinity)

		case .signedOut:
			HomerLoginView(store: store)

		case .signedIn:
			if store.isChangingInstance {
				HomerLoginView(store: store)
			}
			else {
				switch store.tab {
				case .processes:
					HomerProcessListView(store: store)
				case .questions:
					HomerQuestionListView(store: store)
				}
			}
		}
	}

	// MARK: - Header

	private var headerView: some View {
		HStack {
			HStack(spacing: 12) {
				sectionSwitcher

				if showsConsole {
					Picker("Homer page", selection: $store.tab) {
						Text("Processes").tag(HomerConsoleReducer.Tab.processes)
						Text(questionsTabTitle).tag(HomerConsoleReducer.Tab.questions)
					}
					.pickerStyle(.segmented)
					.labelsHidden()
					.fixedSize()
				}
			}

			Spacer()

			if showsConsole, let user = store.user {
				HStack(spacing: 12) {
					Text(HomerEndpoint.displayName(of: store.baseURL))
						.scaledFont(.subheadline)
						.foregroundStyle(.secondary)
						.lineLimit(1)
						.truncationMode(.middle)

					HeaderButton(
						icon: "arrow.clockwise",
						tooltip: "Refresh (⌘R)",
						color: .blue,
						action: { store.send(.refreshTapped) }
					)
					// The repositories' ⌘R is disabled while this section is shown (see
					// `RootRepositoryView`), so this one has the key to itself.
					.keyboardShortcut("r", modifiers: .command)

					HeaderButton(
						icon: "safari",
						tooltip: "Open this page of the web console",
						action: openCurrentPageInWebConsole
					)

					accountMenu(user: user)
				}
			}
		}
		// Matches the repository header's height, which its 30 pt buttons set, so the switcher
		// does not move when the section changes — signed out, this header has no buttons.
		.frame(minHeight: 30)
		.padding()
		.windowTitleBarArea()
	}

	private var questionsTabTitle: String {
		store.openQuestionCount > 0 ? "Questions (\(store.openQuestionCount))" : "Questions"
	}

	private func accountMenu(user: HomerUser) -> some View {
		Menu {
			Text("Signed in as \(user.username)")
			Divider()
			Button {
				store.send(.changeInstanceTapped)
			} label: {
				Label("Change Instance…", systemImage: "server.rack")
			}
			Button {
				store.send(.signOutTapped)
			} label: {
				Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
			}
		} label: {
			Image(systemName: "person.crop.circle")
				.font(.system(size: 16))
				.foregroundStyle(.gray)
		}
		.labelStyle(.titleAndIcon)
		.menuStyle(.borderlessButton)
		.menuIndicator(.hidden)
		.fixedSize()
		.help("Signed in as \(user.username)")
	}

	private func openCurrentPageInWebConsole() {
		switch store.tab {
		case .processes:
			store.send(.openWebConsoleTapped(path: "processes", title: "Processes"))
		case .questions:
			store.send(.openWebConsoleTapped(path: "questions", title: "Questions"))
		}
	}
}

// MARK: - Shared pieces

/// A process status as the console's colored badge shows it.
struct HomerStatusBadge: View {
	let status: HomerProcessStatus

	var body: some View {
		Text(status.title)
			.scaledFont(.caption)
			.fontWeight(.semibold)
			.foregroundStyle(.white)
			.padding(.horizontal, 7)
			.padding(.vertical, 2)
			.background(color, in: Capsule())
	}

	private var color: Color {
		switch status {
		case .working:
			.blue
		case .finished:
			.green
		case .failed:
			.red
		case .killed:
			.orange
		case .created, .unknown:
			.gray
		}
	}
}

/// An inline error under a list's toolbar: the last good data stays below it.
struct HomerErrorBanner: View {
	let message: String

	var body: some View {
		Label(message, systemImage: "exclamationmark.triangle.fill")
			.scaledFont(.callout)
			.foregroundStyle(.red)
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding(.horizontal)
			.padding(.vertical, 6)
			.background(Color.red.opacity(0.08))
	}
}
