import Foundation

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

	public var commandFlag: String {
		switch self {
		case .externalOnly:
			"--external-only"

		case .all:
			""
		}
	}
}
