import ComposableArchitecture
import SwiftUI
import AppUI
import ToolsIntegration

// MARK: - YouTrack Button View

public struct YouTrackButtonView: View {
	@Bindable
	var store: StoreOf<YouTrackButtonReducer>

	/// Read here and applied to the menu's label as a plain font: a `.borderlessButton` menu's
	/// label is flattened by AppKit, which drops `scaledFont`'s environment lookup and keeps only
	/// a font set directly on the `Text`.
	@Environment(\.uiFontScale)
	private var uiFontScale

	public init(store: StoreOf<YouTrackButtonReducer>) {
		self.store = store
	}

	public var body: some View {
		Group {
			if store.isApplying {
				GitOperationProgressView(
					text: "Updating...",
					color: .indigo,
					helpText: "Changing the state of \(store.ticketId)..."
				)
			}
			else {
				Menu {
					YouTrackMenuItems(store: store)
				} label: {
					Text("YouTrack")
						.font(.system(size: 12 * uiFontScale))
				}
				.menuStyle(.borderlessButton)
				.help("Move \(store.ticketId) to a different state")
			}
		}
		.fixedSize()
		.youTrackMenuPresentations(store: store)
	}
}

/// The YouTrack menu as a submenu of another menu (the repository row's "⋯" menu). While a move
/// is being applied it is a disabled entry saying so instead.
///
/// A menu entry cannot present anything, so whoever shows this must also apply
/// `youTrackMenuPresentations(store:)` to a view outside the menu.
public struct YouTrackSubmenu: View {
	let store: StoreOf<YouTrackButtonReducer>

	public init(store: StoreOf<YouTrackButtonReducer>) {
		self.store = store
	}

	public var body: some View {
		if store.isApplying {
			Button {} label: {
				Label("Updating \(store.ticketId)...", systemImage: "list.bullet.rectangle")
			}
			.disabled(true)
		}
		else {
			Menu {
				YouTrackMenuItems(store: store)
			} label: {
				Label("YouTrack", systemImage: "list.bullet.rectangle")
			}
		}
	}
}

public extension View {
	/// The YouTrack menu's error alert. Applied by `YouTrackButtonView` itself; a
	/// `YouTrackSubmenu` needs it on a view outside the menu it sits in.
	func youTrackMenuPresentations(store: StoreOf<YouTrackButtonReducer>) -> some View {
		modifier(YouTrackMenuPresentations(store: store))
	}
}

private struct YouTrackMenuPresentations: ViewModifier {
	@Bindable
	var store: StoreOf<YouTrackButtonReducer>

	func body(content: Content) -> some View {
		content
			.sheet(item: $store.scope(\.$alert, action: \.alert)) { alertStore in
				ScrollableAlertView(store: alertStore)
			}
	}
}

/// The menu's entries, shared by `YouTrackButtonView` and `YouTrackSubmenu`.
private struct YouTrackMenuItems: View {
	let store: StoreOf<YouTrackButtonReducer>

	var body: some View {
		Section(currentStateTitle) {
			ForEach(store.transitions) { transition in
				Button {
					store.send(.transitionTapped(transition))
				} label: {
					Text(transition.presentation)
				}
			}
		}
	}

	/// Phrased as the move being made, not as "ticket · state" — a bare state name in the header
	/// sits inline above the options and reads like a sixth, selectable state, which makes the
	/// menu look like a full state picker rather than the reachable subset it is.
	private var currentStateTitle: String {
		if let currentState = store.currentState {
			"Move from \(currentState.rawValue) to"
		}
		else {
			"Move to"
		}
	}
}

#Preview {
	YouTrackButtonView(
		store: Store(
			initialState: YouTrackButtonReducer.State(
				ticketId: "MOB-1234",
				baseURL: "https://youtrack.example.com",
				stateFieldId: "84-950",
				currentState: .inProgress,
				transitions: [
					TicketStateTransition(eventId: "to review", presentation: "Waiting to code review"),
					TicketStateTransition(eventId: "test feature-bug", presentation: "Waiting for testing"),
					TicketStateTransition(eventId: "to acc", presentation: "Waiting to acceptation"),
					TicketStateTransition(eventId: "reopen", presentation: "Open"),
					TicketStateTransition(eventId: "done", presentation: "Done"),
				]
			),
			reducer: {
				YouTrackButtonReducer()
			}
		)
	)
	.padding()
}
