import Sharing

// MARK: - ToolsIntegration Shared Keys

public nonisolated extension SharedReaderKey where Self == AppStorageKey<String> {
	static var youtrackAuthToken: Self {
		appStorage("youtrackAuthToken")
	}
}

public extension SharedReaderKey where Self == AppStorageKey<TuistCacheType> {
	static var tuistCacheType: Self {
		appStorage("tuistCacheType")
	}
}

public nonisolated extension SharedReaderKey where Self == AppStorageKey<TerminalOpeningBehavior> {
	static var terminalOpeningBehavior: Self {
		appStorage("terminalOpeningBehavior")
	}

	static var claudeCodeOpeningBehavior: Self {
		appStorage("claudeCodeOpeningBehavior")
	}
}
