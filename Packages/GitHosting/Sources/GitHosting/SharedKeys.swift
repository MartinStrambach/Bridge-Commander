import Sharing

public nonisolated extension SharedReaderKey where Self == AppStorageKey<String> {
	static var githubToken: Self {
		appStorage("githubToken")
	}

	static var gitlabToken: Self {
		appStorage("gitlabToken")
	}
}

public nonisolated extension SharedReaderKey where Self == AppStorageKey<GitHubOwnerTokens> {
	/// GitHub tokens for owners `githubToken` does not reach; see `GitHubOwnerTokens`.
	static var githubOwnerTokens: Self {
		appStorage("githubOwnerTokens")
	}
}
