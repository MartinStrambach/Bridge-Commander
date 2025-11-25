import ComposableArchitecture
import Foundation

// MARK: - Git Service Dependency

private struct GitServiceKey: DependencyKey {
	static let liveValue: GitServiceType = GitService()
}

extension DependencyValues {
	var gitService: GitServiceType {
		get { self[GitServiceKey.self] }
		set { self[GitServiceKey.self] = newValue }
	}
}

// MARK: - YouTrack Service Dependency

private struct YouTrackServiceKey: DependencyKey {
	static let liveValue: YouTrackServiceType = YouTrackServiceImpl()
}

extension DependencyValues {
	var youTrackService: YouTrackServiceType {
		get { self[YouTrackServiceKey.self] }
		set { self[YouTrackServiceKey.self] = newValue }
	}
}

// MARK: - Xcode Service Dependency

private struct XcodeServiceKey: DependencyKey {
	static let liveValue: XcodeServiceType = XcodeServiceImpl()
}

extension DependencyValues {
	var xcodeService: XcodeServiceType {
		get { self[XcodeServiceKey.self] }
		set { self[XcodeServiceKey.self] = newValue }
	}
}
