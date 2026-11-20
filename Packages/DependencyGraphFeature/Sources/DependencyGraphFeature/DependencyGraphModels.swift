import Foundation

// MARK: - Platform

/// One of the graphs the sheet switches between.
public enum ModulePlatform: String, CaseIterable, Identifiable, Sendable {
	case kmp
	case android
	case ios

	public var id: Self { self }

	public var title: String {
		switch self {
		case .kmp: "KMP"
		case .android: "Android"
		case .ios: "iOS"
		}
	}
}

// MARK: - Module

/// What builds a module, which decides the graph it belongs to.
public enum ModuleKind: String, Sendable {
	/// A Gradle module applying the Kotlin Multiplatform plugin.
	case kmp
	/// A Gradle Android library, application or test module.
	case android
	/// A plain JVM Gradle module (java-library, kotlin.jvm). Shown with Android, the other
	/// JVM-only side of the build.
	case jvm
	/// A Tuist framework target.
	case iosFramework
	/// A Tuist app extension target.
	case iosExtension

	public var platform: ModulePlatform {
		switch self {
		case .kmp: .kmp
		case .android, .jvm: .android
		case .iosFramework, .iosExtension: .ios
		}
	}

	public var title: String {
		switch self {
		case .kmp: "Kotlin Multiplatform module"
		case .android: "Android module"
		case .jvm: "JVM module"
		case .iosFramework: "iOS framework"
		case .iosExtension: "iOS app extension"
		}
	}
}

public struct DependencyModule: Identifiable, Hashable, Sendable {
	/// A Gradle project path (":core:ui") or "ios:" plus the target's name, so the two never
	/// collide.
	public let id: String
	public let kind: ModuleKind
	/// Folders the module's sources live in, relative to the repository root, without a trailing
	/// slash. A changed file belongs to the module with the longest matching folder.
	public let directories: [String]

	public init(id: String, kind: ModuleKind, directories: [String]) {
		self.id = id
		self.kind = kind
		self.directories = directories
	}

	/// The Gradle path or the target's name.
	public var name: String {
		id.hasPrefix(Self.iosPrefix) ? String(id.dropFirst(Self.iosPrefix.count)) : id
	}

	/// The node's first line: the last path segment, with its parent's when the segment alone
	/// says little (":news:api" → "news:api").
	public var title: String {
		guard kind.platform != .ios else {
			return name
		}

		let segments = name.split(separator: ":").map(String.init)
		guard let last = segments.last else {
			return name
		}
		if segments.count > 1, Self.genericSegments.contains(last) {
			return "\(segments[segments.count - 2]):\(last)"
		}
		return last
	}

	/// The node's second line: the Gradle path above the title, or the folder of a top-level
	/// module (":core-ui" lives in "android/core-ui"); what an iOS target is.
	public var subtitle: String {
		guard kind.platform != .ios else {
			return kind.title
		}

		let segments = name.split(separator: ":")
		let titleSegmentCount = title.split(separator: ":").count
		let parent = segments.dropLast(titleSegmentCount)
		guard parent.isEmpty else {
			return ":" + parent.joined(separator: ":")
		}
		return directories.first ?? kind.title
	}

	static let iosPrefix = "ios:"

	private static let genericSegments: Set<String> = [
		"api", "impl", "testing", "test", "core", "ui", "fake", "fakes", "model", "data", "domain", "common",
	]
}

// MARK: - Edge

/// `from` depends on `to`.
public struct DependencyEdge: Hashable, Sendable {
	public let from: String
	public let to: String
	/// Declared only for tests (a test configuration or source set, or a tests target).
	public let isTest: Bool

	public init(from: String, to: String, isTest: Bool) {
		self.from = from
		self.to = to
		self.isTest = isTest
	}
}

// MARK: - Graph

/// Every module the repository's build files declare, across all platforms.
public struct DependencyGraph: Equatable, Sendable {
	public var modules: [DependencyModule]
	public var edges: [DependencyEdge]

	public init(modules: [DependencyModule], edges: [DependencyEdge]) {
		self.modules = modules.sorted { $0.id < $1.id }
		self.edges = Self.deduplicated(edges)
	}

	/// The platforms with at least one module, in tab order.
	public var platforms: [ModulePlatform] {
		let present = Set(modules.map(\.kind.platform))
		return ModulePlatform.allCases.filter(present.contains)
	}

	/// One edge per pair, a test edge only when no regular declaration exists; self edges dropped.
	static func deduplicated(_ edges: [DependencyEdge]) -> [DependencyEdge] {
		var isTestByPair: [Pair: Bool] = [:]
		for edge in edges where edge.from != edge.to {
			let pair = Pair(from: edge.from, to: edge.to)
			isTestByPair[pair] = (isTestByPair[pair] ?? true) && edge.isTest
		}
		return isTestByPair
			.map { DependencyEdge(from: $0.key.from, to: $0.key.to, isTest: $0.value) }
			.sorted { ($0.from, $0.to) < ($1.from, $1.to) }
	}

	private struct Pair: Hashable {
		let from: String
		let to: String
	}
}

// MARK: - Branch changes

/// Which modules the current branch added or changed.
public struct ModuleChanges: Equatable, Sendable {
	/// What the branch was compared with, e.g. "origin/master".
	public var baseRef: String
	public var mergeBase: String
	/// Modules none of whose folders existed at the merge-base.
	public var newModules: Set<String>
	/// Modules that existed at the merge-base and own a changed file.
	public var changedModules: Set<String>
	/// Changed files per module, new modules included.
	public var changedFileCounts: [String: Int]

	public init(
		baseRef: String,
		mergeBase: String,
		newModules: Set<String>,
		changedModules: Set<String>,
		changedFileCounts: [String: Int]
	) {
		self.baseRef = baseRef
		self.mergeBase = mergeBase
		self.newModules = newModules
		self.changedModules = changedModules
		self.changedFileCounts = changedFileCounts
	}

	public enum Status: Equatable, Sendable {
		case new
		case changed
	}

	public func status(of moduleID: String) -> Status? {
		if newModules.contains(moduleID) {
			return .new
		}
		if changedModules.contains(moduleID) {
			return .changed
		}
		return nil
	}
}
