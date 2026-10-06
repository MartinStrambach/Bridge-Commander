import AppKit
import ComposableArchitecture
import Observation
import TerminalFeature

/// The app's repository state and its terminal panes, owned by the app rather than the main
/// window so that the menu bar extra can show them while the window is closed — and so that
/// closing the window no longer hangs up every shell.
///
/// Work that used to start and stop with the window starts here instead: the launch (scan,
/// periodic refresh, tab restore), saving the tabs at quit, and hanging up the shell of any
/// session that leaves the state.
@MainActor
public final class RepositoryAppModel {
	/// The `Window` scene's id, for `openWindow(id:)`.
	public static let mainWindowId = "main"

	let store: StoreOf<RepositoryListReducer>
	let terminalViewStore = TerminalViewStore()

	private var notificationObservers: [NSObjectProtocol] = []

	public init() {
		self.store = Store(initialState: RepositoryListReducer.State()) {
			RepositoryListReducer()
		}

		let center = NotificationCenter.default
		notificationObservers = [
			// Created with the app, before it has finished launching.
			center.addObserver(
				forName: NSApplication.didFinishLaunchingNotification,
				object: nil,
				queue: .main
			) { [weak self] _ in
				MainActor.assumeIsolated {
					_ = self?.store.send(.appLaunched)
				}
			},
			center.addObserver(
				forName: NSApplication.willTerminateNotification,
				object: nil,
				queue: .main
			) { [weak self] _ in
				MainActor.assumeIsolated {
					self?.saveTerminalTabs()
				}
			},
		]
		hangUpRemovedSessions()
	}

	/// Records the open tabs for the next launch. The shells' directories and Claude conversations
	/// are read here because only the panes know them; the reducer writes the file before `send`
	/// returns — while Claude is still running, before quitting hangs it up.
	private func saveTerminalTabs() {
		store.send(.view(.saveTerminalTabsRequested(panes: terminalViewStore.paneSnapshots())))
	}

	/// The reducer can drop a session without going through the buttons that kill panes directly,
	/// as it does when a worktree is deleted. Whatever the reason, a session that has left the
	/// state must hang up its shell rather than run on unseen — window or no window.
	private func hangUpRemovedSessions() {
		let ids = withObservationTracking {
			store.terminalSessions.ids
		} onChange: { [weak self] in
			// `onChange` fires before the change lands; read the new ids after it.
			Task { @MainActor in
				self?.hangUpRemovedSessions()
			}
		}
		terminalViewStore.killSessions(notIn: Set(ids))
	}
}
