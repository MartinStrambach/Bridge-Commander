import ComposableArchitecture
import SwiftUI
import AppUI
import ToolsIntegration

// MARK: - YouTrack Button View

public struct YouTrackButtonView: View {
	@Bindable
	var store: StoreOf<YouTrackButtonReducer>

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
				PopUpMenuButton("YouTrack") {
					store.menuEntries
				}
				.help("Move \(store.ticketId) to a different state")
			}
		}
		.fixedSize()
		.youTrackMenuPresentations(store: store)
	}
}

public extension Store where State == YouTrackButtonReducer.State, Action == YouTrackButtonReducer.Action {
	/// The YouTrack menu as an entry of another menu (the repository row's "⋯" menu): a submenu,
	/// or while a move is being applied a disabled entry saying so.
	///
	/// A menu entry cannot present anything, so whoever shows this must also apply
	/// `youTrackMenuPresentations(store:)` to a view outside the menu.
	var submenuEntry: PopUpMenuEntry {
		if self.isApplying {
			.action(PopUpMenuAction("Updating \(self.ticketId)...", systemImage: "list.bullet.rectangle", isEnabled: false) {})
		}
		else {
			.submenu("YouTrack", systemImage: "list.bullet.rectangle") {
				self.menuEntries
			}
		}
	}
}

public extension View {
	/// The YouTrack menu's error alert. Applied by `YouTrackButtonView` itself; a
	/// `submenuEntry` needs it on a view outside the menu it sits in.
	func youTrackMenuPresentations(store: StoreOf<YouTrackButtonReducer>) -> some View {
		modifier(YouTrackMenuPresentations(store: store))
	}
}

private struct YouTrackMenuPresentations: ViewModifier {
	@Bindable
	var store: StoreOf<YouTrackButtonReducer>

	@Environment(\.presentsButtonAlerts)
	private var presentsAlerts

	func body(content: Content) -> some View {
		content
			.sheet(item: presentsAlerts ? $store.scope(\.$alert, action: \.alert) : .constant(nil)) { alertStore in
				ScrollableAlertView(store: alertStore)
			}
	}
}

/// The menu's entries, shared by `YouTrackButtonView` and `submenuEntry`.
private extension Store where State == YouTrackButtonReducer.State, Action == YouTrackButtonReducer.Action {
	@PopUpMenuBuilder
	var menuEntries: [PopUpMenuEntry] {
		PopUpMenuEntry.section(currentStateTitle) {
			for transition in self.transitions {
				PopUpMenuAction(transition.presentation) {
					self.send(.transitionTapped(transition))
				}
			}
		}
	}

	/// Phrased as the move being made, not as "ticket · state" — a bare state name in the header
	/// sits inline above the options and reads like a sixth, selectable state, which makes the
	/// menu look like a full state picker rather than the reachable subset it is.
	private var currentStateTitle: String {
		if let currentState = self.currentState {
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
