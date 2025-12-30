import ComposableArchitecture
import Foundation

// MARK: - App Storage Shared Keys

extension SharedReaderKey where Self == AppStorageKey<String> {
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
