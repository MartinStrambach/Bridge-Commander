import ComposableArchitecture
import Foundation

// MARK: - App Storage Shared Keys

nonisolated extension SharedReaderKey where Self == AppStorageKey<String> {
	static var youtrackAuthToken: Self {
		appStorage("youtrackAuthToken")
	}

	static var iosSubfolderPath: Self {
		appStorage("iosSubfolderPath")
	}

	static var mobileSubfolderPath: Self {
		appStorage("mobileSubfolderPath")
	}

	static var ticketIdRegex: Self {
		appStorage("ticketIdRegex")
	}

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

extension SharedReaderKey where Self == AppStorageKey<PeriodicRefreshInterval> {
	static var periodicRefreshInterval: Self {
		appStorage("periodicRefreshInterval")
	}
}

extension SharedReaderKey where Self == AppStorageKey<Bool> {
	static var openXcodeAfterGenerate: Self {
		appStorage("openXcodeAfterGenerate")
	}

	static var deleteDerivedDataOnWorktreeDelete: Self {
		appStorage("deleteDerivedDataOnWorktreeDelete")
	}
}

extension SharedReaderKey where Self == AppStorageKey<TuistCacheType> {
	static var tuistCacheType: Self {
		appStorage("tuistCacheType")
	}
}

nonisolated extension SharedReaderKey where Self == AppStorageKey<TerminalOpeningBehavior> {
	static var terminalOpeningBehavior: Self {
		appStorage("terminalOpeningBehavior")
	}

	static var claudeCodeOpeningBehavior: Self {
		appStorage("claudeCodeOpeningBehavior")
	}
}

nonisolated extension SharedReaderKey where Self == AppStorageKey<TerminalColorTheme> {
	static var terminalColorTheme: Self {
		appStorage("terminalColorTheme")
	}
}

nonisolated extension SharedReaderKey where Self == FileStorageKey<[String]> {
	static var trackedRepoPaths: Self {
		.fileStorage(applicationSupportURL(name: "trackedRepoPaths.json"))
	}

	static var collapsedRepoPaths: Self {
		.fileStorage(applicationSupportURL(name: "collapsedRepoPaths.json"))
	}
}

private nonisolated func applicationSupportURL(name: String) -> URL {
	let urls = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
	let appSupport = urls.first ?? URL(fileURLWithPath: NSHomeDirectory()).appending(component: "Library/Application Support")
	return appSupport
		.appending(component: Bundle.main.bundleIdentifier ?? "BridgeCommander")
		.appending(component: name)
}
