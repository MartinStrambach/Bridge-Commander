import Foundation
import Sharing

// MARK: - App Storage Shared Keys

public nonisolated extension SharedReaderKey where Self == AppStorageKey<String> {
	static var branchNameRegex: Self {
		appStorage("branchNameRegex")
	}

	static var androidStudioPath: Self {
		appStorage("androidStudioPath")
	}

	static var worktreeBasePath: Self {
		appStorage("worktreeBasePath")
	}
}

public extension SharedReaderKey where Self == AppStorageKey<PeriodicRefreshInterval> {
	static var periodicRefreshInterval: Self {
		appStorage("periodicRefreshInterval")
	}
}

public extension SharedReaderKey where Self == AppStorageKey<Bool> {
	static var openXcodeAfterGenerate: Self {
		appStorage("openXcodeAfterGenerate")
	}

	static var deleteDerivedDataOnWorktreeDelete: Self {
		appStorage("deleteDerivedDataOnWorktreeDelete")
	}

	/// Whether highlighting text in the built-in terminal copies it to the pasteboard right away.
	/// Off by default: every highlight would otherwise overwrite whatever the user had copied
	/// elsewhere and meant to paste into the terminal.
	static var terminalCopyOnSelect: Self {
		appStorage("terminalCopyOnSelect")
	}
}

public nonisolated extension SharedReaderKey where Self == AppStorageKey<TerminalThemeSelection> {
	/// Keeps the key the built-in-only setting used: a `TerminalThemeSelection` raw value for a
	/// built-in theme is the bare theme name, so a previously stored theme migrates by itself.
	static var terminalColorTheme: Self {
		appStorage("terminalColorTheme")
	}
}

public nonisolated extension SharedReaderKey where Self == FileStorageKey<[TerminalProfile]> {
	/// Color profiles imported from Terminal.app. On disk rather than in user defaults: a
	/// profile carries 20 colors, and defaults are the wrong place for payloads that size.
	static var terminalProfiles: Self {
		.fileStorage(applicationSupportURL(name: "terminalProfiles.json"))
	}
}

public nonisolated extension SharedReaderKey where Self == FileStorageKey<[String]> {
	static var trackedRepoPaths: Self {
		.fileStorage(applicationSupportURL(name: "trackedRepoPaths.json"))
	}

	static var collapsedRepoPaths: Self {
		.fileStorage(applicationSupportURL(name: "collapsedRepoPaths.json"))
	}
}

public nonisolated extension SharedReaderKey where Self == FileStorageKey<[String: RepoGroupSettings]> {
	static var groupSettings: Self {
		.fileStorage(applicationSupportURL(name: "groupSettings.json"))
	}
}

private nonisolated func applicationSupportURL(name: String) -> URL {
	let urls = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
	let appSupport = urls.first ?? URL(fileURLWithPath: NSHomeDirectory())
		.appending(component: "Library/Application Support")
	return appSupport
		.appending(component: Bundle.main.bundleIdentifier ?? "BridgeCommander")
		.appending(component: name)
}
