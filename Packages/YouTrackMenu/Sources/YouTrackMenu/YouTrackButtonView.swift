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

	@Environment(\.presentsButtonAlerts)
	private var presentsAlerts

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
					Section(currentStateTitle) {
						ForEach(store.transitions) { transition in
							Button {
								store.send(.transitionTapped(transition))
							} label: {
								Text(transition.presentation)
							}
						}
					}
				} label: {
					Text("YouTrack")
						.font(.system(size: 12 * uiFontScale))
				}
				.menuStyle(.borderlessButton)
				.help("Move \(store.ticketId) to a different state")
			}
		}
		.fixedSize()
		.sheet(item: presentsAlerts ? $store.scope(\.$alert, action: \.alert) : .constant(nil)) { alertStore in
			ScrollableAlertView(store: alertStore)
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
