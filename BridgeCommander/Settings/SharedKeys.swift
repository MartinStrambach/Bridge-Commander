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

	static var ticketIdRegex: Self {
		appStorage("ticketIdRegex")
	}

	static var branchNameRegex: Self {
		appStorage("branchNameRegex")
	}

	static var androidStudioPath: Self {
		appStorage("androidStudioPath")
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
