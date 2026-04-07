import Sharing

// MARK: - ToolsIntegration Shared Keys

public nonisolated extension SharedReaderKey where Self == AppStorageKey<String> {
	static var youtrackAuthToken: Self {
		appStorage("youtrackAuthToken")
	}

	static var misePath: Self {
		appStorage("misePath")
	}
}

public nonisolated extension SharedReaderKey where Self == AppStorageKey<TuistRunMode> {
	static var tuistRunMode: Self {
		appStorage("tuistRunMode")
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

public nonisolated extension SharedReaderKey where Self == AppStorageKey<TerminalApp> {
	static var terminalApp: Self {
		appStorage("terminalApp")
	}
}
