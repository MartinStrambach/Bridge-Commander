import AppUI
import ComposableArchitecture
import SwiftUI

/// The Homer section of the main window. `sectionSwitcher` heads it, in the place it holds in
/// every section's header; the instance menu at the other end switches between the instances
/// (⌘1…⌘9 too), each of which stays signed in.
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
	}

	private var selectedInstanceStore: StoreOf<HomerInstanceReducer>? {
		let id = store.selectedInstanceID
		return store.scope(\.instances[id: id], action: \.instances[id: id])
	}

	/// The selected instance's lists, as opposed to a sign-in form or a progress spinner.
	private var showsConsole: Bool {
		store.addInstance == nil && store.selectedInstance?.user != nil
	}

	@ViewBuilder
	private var content: some View {
		if let addInstanceStore = store.scope(\.addInstance, action: \.addInstance) {
			HomerLoginView(store: addInstanceStore)
		}
		else if let instanceStore = selectedInstanceStore {
			HomerInstanceView(store: instanceStore, tab: store.tab)
				// A fresh view per instance: the table's selection and the form's focus are its own.
				.id(store.selectedInstanceID)
		}
	}

	// MARK: - Header

	private var headerView: some View {
		HStack {
			HStack(spacing: 12) {
				sectionSwitcher

				if showsConsole {
					Picker("Homer page", selection: $store.tab) {
						ForEach(availableTabs, id: \.self) { tab in
							Text(tab == .questions ? questionsTabTitle : tab.title).tag(tab)
						}
					}
					.pickerStyle(.segmented)
					.labelsHidden()
					.fixedSize()
				}
			}

			Spacer()

			HStack(spacing: 12) {
				if !store.instances.isEmpty {
					instanceMenu
				}

				if showsConsole, let instance = store.selectedInstance, let user = instance.user {
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

					accountMenu(user: user, instanceID: instance.id)
				}
			}
		}
		// Matches the repository header's height, which its 30 pt buttons set, so the switcher
		// does not move when the section changes — signed out, this header has no buttons.
		.frame(minHeight: 30)
		.padding()
		.windowTitleBarArea()
		.background { instanceShortcuts }
	}

	/// The pages the signed-in user may see: the admin-only ones only for an admin, as in the
	/// console's sidebar. The page on screen stays listed, so the picker never loses its
	/// selection — the page itself says it is not available.
	private var availableTabs: [HomerConsoleReducer.Tab] {
		let isAdmin = store.selectedInstance?.user?.isAdmin == true
		return HomerConsoleReducer.Tab.allCases.filter { !$0.isAdminOnly || isAdmin || $0 == store.tab }
	}

	private var questionsTabTitle: String {
		let count = store.selectedInstance?.openQuestionCount ?? 0
		return count > 0 ? "Questions (\(count))" : "Questions"
	}

	// MARK: - Instances

	private var instanceMenu: some View {
		HStack(spacing: 6) {
			Menu {
				ForEach(Array(store.instances.enumerated()), id: \.element.id) { index, instance in
					Toggle(isOn: Binding(
						get: { store.addInstance == nil && instance.id == store.selectedInstanceID },
						set: { _ in store.send(.instanceSelected(instance.id)) }
					)) {
						Text(Self.menuTitle(of: instance))
					}
					.keyboardShortcut(Self.shortcutKey(index: index).map { KeyboardShortcut($0, modifiers: .command) })
				}
				Divider()
				Button {
					store.send(.addInstanceTapped)
				} label: {
					Label("Add Instance…", systemImage: "plus")
				}
				if store.addInstance == nil, let instance = store.selectedInstance {
					Button(role: .destructive) {
						store.send(.removeInstanceTapped(instance.id))
					} label: {
						Label(
							"Remove \(HomerEndpoint.displayName(of: instance.baseURL))",
							systemImage: "minus.circle"
						)
					}
				}
			} label: {
				Label(menuLabel, systemImage: "server.rack")
			}
			.labelStyle(.titleAndIcon)
			.menuStyle(.borderlessButton)
			.fixedSize()
			.help("Switch Homer instance (⌘1–⌘9), or add one")

			let elsewhere = store.otherInstancesOpenQuestionCount
			if elsewhere > 0 {
				HomerQuestionCountBadge(count: elsewhere)
					.help("\(elsewhere) open \(elsewhere == 1 ? "question" : "questions") on your other instances")
			}
		}
	}

	private var menuLabel: String {
		guard store.addInstance == nil, let instance = store.selectedInstance else {
			return "New Instance"
		}
		return HomerEndpoint.displayName(of: instance.baseURL)
	}

	/// ⌘1…⌘9, the menu's order. The menu items carry the same shortcuts, but a closed menu does
	/// not answer them reliably; selecting the instance on screen again does nothing, so the
	/// two never fight.
	private var instanceShortcuts: some View {
		ForEach(Array(store.instances.ids.prefix(HomerConsoleReducer.shortcutInstanceLimit).enumerated()), id: \.element) { index, id in
			if let key = Self.shortcutKey(index: index) {
				Button("") { store.send(.instanceSelected(id)) }
					.keyboardShortcut(key, modifiers: .command)
					.hidden()
			}
		}
	}

	private static func shortcutKey(index: Int) -> KeyEquivalent? {
		index < HomerConsoleReducer.shortcutInstanceLimit ? KeyEquivalent(Character(String(index + 1))) : nil
	}

	/// An instance as the menu lists it: its name, who is signed in, and its open questions.
	static func menuTitle(of instance: HomerInstanceReducer.State) -> String {
		let name = HomerEndpoint.displayName(of: instance.baseURL)
		switch instance.session {
		case .checking:
			return "\(name) — connecting…"
		case .signedOut:
			return instance.signIn.sessionExpired ? "\(name) — session expired" : "\(name) — signed out"
		case let .signedIn(user):
			let count = instance.openQuestionCount
			guard count > 0 else {
				return "\(name) — \(user.username)"
			}
			return "\(name) — \(user.username) · \(count) open \(count == 1 ? "question" : "questions")"
		}
	}

	private func accountMenu(user: HomerUser, instanceID: HomerInstanceReducer.State.ID) -> some View {
		Menu {
			Text("Signed in as \(user.username)")
			Divider()
			Button {
				store.send(.instances(.element(id: instanceID, action: .signOutTapped)))
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
		store.send(.openWebConsoleTapped(path: store.tab.webConsolePath, title: store.tab.title))
	}
}

/// The selected instance: its sign-in form while signed out, otherwise the page the header's
/// picker chose.
struct HomerInstanceView: View {
	@Bindable
	var store: StoreOf<HomerInstanceReducer>
	let tab: HomerConsoleReducer.Tab

	var body: some View {
		Group {
			switch store.session {
			case .checking:
				ProgressView("Connecting to \(HomerEndpoint.displayName(of: store.baseURL))…")
					.frame(maxWidth: .infinity, maxHeight: .infinity)

			case .signedOut:
				HomerLoginView(store: store.scope(\.signIn, action: \.signIn))

			case let .signedIn(user):
				if tab.isAdminOnly, !user.isAdmin {
					ContentUnavailableView(
						"Admins Only",
						systemImage: "lock",
						description: Text("You don’t have access to this page.")
					)
				}
				else {
					switch tab {
					case .processes:
						HomerProcessListView(store: store)
					case .questions:
						HomerQuestionListView(store: store)
					case .continuations:
						HomerContinuationsView(store: store.scope(\.continuations, action: \.continuations))
					case .schedules:
						HomerSchedulesView(store: store.scope(\.agents, action: \.agents))
					case .agents:
						HomerAgentsView(store: store.scope(\.agents, action: \.agents), user: user)
					case .costs:
						HomerCostsView(store: store.scope(\.costs, action: \.costs))
					}
				}
			}
		}
		.sheet(item: $store.webPage) { page in
			HomerWebPageView(page: page)
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
