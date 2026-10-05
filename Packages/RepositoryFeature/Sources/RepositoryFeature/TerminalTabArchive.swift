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
	var tabIndex: Int
	/// The tab the repository was showing (`lastActiveSessionByRepo`).
	var isRepositoryCurrentTab: Bool
	/// The tab on screen; no tab has it when the panel was closed.
	var isOnScreen: Bool
}

/// Every open tab, in tab-bar order.
struct SavedTerminalTabs: Codable, Equatable, Sendable {
	var tabs: [SavedTerminalTab] = []

	/// Takes the session list as it stands. Failed tabs are left out — their shell is gone, and the
	/// user had not asked for it to be retried.
	///
	/// - Parameter panes: What each pane is doing. A session missing from it (one whose pane was
	///   never created, because the panel has not been opened since the tabs were restored) keeps
	///   the directory it starts in and the conversation it was going to resume — nothing has
	///   happened in it since.
	init(
		sessions: IdentifiedArrayOf<TerminalSession>,
		layout: TerminalLayoutReducer.State?,
		panes: [UUID: TerminalPaneSnapshot]
	) {
		tabs = sessions
			.filter(\.status.isLive)
			.map { session in
				SavedTerminalTab(
					repositoryPath: session.repositoryPath,
					directory: panes[session.id]?.directory ?? session.startingDirectory,
					startupCommand: session.startupCommand,
					claudeSessionId: panes[session.id].map(\.claudeSessionId) ?? session.resumedClaudeSessionId,
					tabIndex: session.tabIndex,
					isRepositoryCurrentTab: layout?.lastActiveSessionByRepo[session.repositoryPath] == session.id,
					isOnScreen: layout?.activeSessionId == session.id
				)
			}
	}

	init(tabs: [SavedTerminalTab]) {
		self.tabs = tabs
	}

	/// Drops what can no longer be reopened: a tab whose repository is gone (a worktree deleted
	/// while the app was closed) is dropped, and one whose directory alone is gone reopens at the
	/// repository's root — a shell asked to start in a missing directory never starts.
	func pruned(directoryExists: (String) -> Bool) -> Self {
		Self(
			tabs: tabs.compactMap { tab in
				guard directoryExists(tab.repositoryPath) else {
					return nil
				}

				var tab = tab
				if !directoryExists(tab.directory) {
					tab.directory = tab.repositoryPath
				}
				return tab
			}
		)
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
