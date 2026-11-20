import Foundation
import ComposableArchitecture

// The sheet's view options, remembered across sheets and launches.

public nonisolated extension SharedReaderKey where Self == AppStorageKey<ModulePlatform> {
	static var dependencyGraphPlatform: Self {
		appStorage("dependencyGraphPlatform")
	}
}

public nonisolated extension SharedReaderKey where Self == AppStorageKey<Bool> {
	static var dependencyGraphHighlightsChanges: Self {
		appStorage("dependencyGraphHighlightsChanges")
	}

	static var dependencyGraphShowsOtherPlatforms: Self {
		appStorage("dependencyGraphShowsOtherPlatforms")
	}

	static var dependencyGraphIncludesTestDependencies: Self {
		appStorage("dependencyGraphIncludesTestDependencies")
	}

	static var dependencyGraphShowsIndirectEdges: Self {
		appStorage("dependencyGraphShowsIndirectEdges")
	}
}
