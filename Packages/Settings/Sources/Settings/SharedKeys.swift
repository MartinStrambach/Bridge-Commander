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
}

public nonisolated extension SharedReaderKey where Self == AppStorageKey<TerminalColorTheme> {
	static var terminalColorTheme: Self {
		appStorage("terminalColorTheme")
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
