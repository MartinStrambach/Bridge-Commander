import ComposableArchitecture
import Foundation
import TerminalFeature

/// A built-in terminal tab as it was when the window last closed, so the next launch can reopen it.
struct SavedTerminalTab: Codable, Equatable, Sendable {
	var repositoryPath: String
	/// Where the tab's shell was, not where it started: reopening the tab puts the user back in
	/// the directory they had `cd`'d to.
	var directory: String
	/// The command the tab ran when it opened, typed again when it reopens. Saved as the command
	/// itself rather than recomputed from the settings, because a relaunch restores the tabs before
	/// the scan has found which repository group each one belongs to.
	var startupCommand: String?
	/// The Claude Code conversation running in the tab, which reopening it resumes. When there is
	/// one it is typed instead of `startupCommand`: resuming the conversation is what reopening a
	/// tab that was in Claude means, and starting a fresh Claude beside it would be a second one.
	var claudeSessionId: String?
	/// The title the tab's program last set, shown again until a program in the reopened tab sets
	/// one — a resumed Claude does once it is back up. Absent from tabs saved before titles were.
	var title: String?
	var tabIndex: Int
	/// The tab the repository was showing (`lastActiveSessionByRepo`).
	var isRepositoryCurrentTab: Bool
	/// The tab with the keyboard. No tab has it when the panel had shown nothing yet, and, in a
	/// file written before a hidden panel's panes were saved, when the panel was hidden.
	var isOnScreen: Bool
	/// The pane of the split the tab belonged to, from the left, when the panel showed several
	/// side by side. Nil for a tab that was in none, and in a file written before the panel
	/// could split.
	var paneIndex: Int?
	/// Whether the tab was the one its pane showed. Nil in a file written before panes had tabs
	/// of their own, where a tab with a `paneIndex` is the one its pane showed.
	var isPaneCurrentTab: Bool?
}

/// Every open tab, in tab-bar order.
struct SavedTerminalTabs: Codable, Equatable, Sendable {
	var tabs: [SavedTerminalTab] = []
	/// Whether the panel was on screen. Nil in a file written before a hidden panel's panes were
	/// saved, where a tab with the keyboard means it was.
	var isPanelVisible: Bool?

	/// Takes the session list as it stands. Failed tabs are left out — their shell is gone, and the
	/// user had not asked for it to be retried — and so are run tabs, whose command reopened would
	/// build and launch the app again.
	///
	/// - Parameter panes: What each pane is doing. A session missing from it (one whose pane was
	///   never created, because the panel has not been opened since the tabs were restored) keeps
	///   the directory it starts in and the conversation it was going to resume — nothing has
	///   happened in it since.
	init(_ terminals: TerminalTabs, panes: [UUID: TerminalPaneSnapshot]) {
		let saved = terminals.sessions.filter { $0.status.isLive && !$0.isRunTab }
		// The tab each pane comes back showing: its own, or its first that is saved when its own
		// is not (a run tab, a failed one). A pane with no saved tab does not come back.
		let shownByPane = terminals.panes.map { pane in
			saved[id: pane.shown]?.id ?? pane.tabs.first { saved[id: $0] != nil }
		}
		// The keyboard stays in its pane when that comes back, and otherwise goes to the first
		// that does, so the panel is not lost with the one tab that is not saved.
		let keyboard = (shownByPane.indices.contains(terminals.activePaneIndex) ? shownByPane[terminals.activePaneIndex] : nil)
			?? shownByPane.lazy.compactMap(\.self).first
		let isSplit = shownByPane.count { $0 != nil } > 1
		// Saved whether or not the panel is on screen: hiding keeps the panes, and a panel hidden
		// at quit comes back hidden with them, its tabs' shells starting the first time it opens.
		isPanelVisible = terminals.isPanelVisible
		tabs = saved
			.map { session in
				let paneIndex = isSplit ? terminals.paneIndex(owning: session.id) : nil
				return SavedTerminalTab(
					repositoryPath: session.repositoryPath,
					directory: panes[session.id]?.directory ?? session.startingDirectory,
					startupCommand: session.startupCommand,
					claudeSessionId: panes[session.id].map(\.claudeSessionId) ?? session.resumedClaudeSessionId,
					title: session.title,
					tabIndex: session.tabIndex,
					isRepositoryCurrentTab: terminals.lastActiveSessionByRepo[session.repositoryPath] == session.id,
					isOnScreen: keyboard == session.id,
					paneIndex: paneIndex,
					isPaneCurrentTab: paneIndex.map { shownByPane[$0] == session.id }
				)
			}
	}

	init(tabs: [SavedTerminalTab], isPanelVisible: Bool? = nil) {
		self.tabs = tabs
		self.isPanelVisible = isPanelVisible
	}

	/// Drops what can no longer be reopened: a tab whose repository is gone (a worktree deleted
	/// while the app was closed) is dropped, and one whose directory alone is gone reopens at the
	/// repository's root — a shell asked to start in a missing directory never starts.
	func pruned(directoryExists: (String) -> Bool) -> Self {
		// A copy with its tabs replaced, so whatever else the file says comes through.
		var pruned = self
		pruned.tabs = tabs.compactMap { tab in
			guard directoryExists(tab.repositoryPath) else {
				return nil
			}

			var tab = tab
			if !directoryExists(tab.directory) {
				tab.directory = tab.repositoryPath
			}
			return tab
		}
		return pruned
	}
}

/// Reads and writes `SavedTerminalTabs`.
///
/// A plain file client rather than `@Shared(.fileStorage)`: the tabs are written as the app quits,
/// and a file-storage write that lands within a second of the previous one is deferred to a timer
/// that will not get to run. This one writes before returning.
@DependencyClient
struct TerminalTabArchiveClient: Sendable {
	/// The saved tabs, already pruned of anything that no longer exists on disk.
	var load: @Sendable () -> SavedTerminalTabs? = { nil }
	var save: @Sendable (_ tabs: SavedTerminalTabs) -> Void
}

extension TerminalTabArchiveClient: DependencyKey {
	static let liveValue: Self = {
		let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
			.appending(component: Bundle.main.bundleIdentifier ?? "BridgeCommander")
			.appending(component: "terminalTabs.json")

		return Self(
			load: {
				guard
					let data = try? Data(contentsOf: url),
					let saved = try? JSONDecoder().decode(SavedTerminalTabs.self, from: data)
				else {
					return nil
				}

				return saved.pruned { path in
					var isDirectory: ObjCBool = false
					return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
						&& isDirectory.boolValue
				}
			},
			save: { tabs in
				guard let data = try? JSONEncoder().encode(tabs) else {
					return
				}

				try? FileManager.default.createDirectory(
					at: url.deletingLastPathComponent(),
					withIntermediateDirectories: true
				)
				try? data.write(to: url, options: .atomic)
			}
		)
	}()

	static let testValue = Self()
}
