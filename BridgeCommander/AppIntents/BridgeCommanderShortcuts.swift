import AppIntents

struct BridgeCommanderShortcuts: AppShortcutsProvider {
	static var appShortcuts: [AppShortcut] {
		AppShortcut(
			intent: CreateWorktreeIntent(),
			phrases: [
				"Create a worktree in \(.applicationName)",
				"Create a \(.applicationName) worktree",
				"Create a worktree for \(\.$repository) in \(.applicationName)",
				"New \(.applicationName) worktree for \(\.$repository)",
			],
			shortTitle: "Create Worktree",
			systemImageName: "plus.square.on.square"
		)
	}
}
