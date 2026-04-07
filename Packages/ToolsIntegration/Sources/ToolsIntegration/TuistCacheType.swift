import Foundation

// MARK: - Tuist Run Mode

public nonisolated enum TuistRunMode: String, Equatable, CaseIterable, Codable, Sendable {
	case mise
	case native

	public var displayName: String {
		switch self {
		case .mise:
			"mise"
		case .native:
			"Native"
		}
	}
}

// MARK: - Tuist Cache Type

public nonisolated enum TuistCacheType: String, Equatable, CaseIterable, Sendable {
	case externalOnly
	case all

	public var displayName: String {
		switch self {
		case .externalOnly:
			"External Only"

		case .all:
			"All Targets"
		}
	}

	internal var commandFlag: String {
		switch self {
		case .externalOnly:
			"--external-only"

		case .all:
			""
		}
	}
}
