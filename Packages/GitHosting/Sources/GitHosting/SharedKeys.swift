import Sharing

public nonisolated extension SharedReaderKey where Self == AppStorageKey<String> {
	static var githubToken: Self {
		appStorage("githubToken")
	}

	static var gitlabToken: Self {
		appStorage("gitlabToken")
	}
}
