import Foundation

public nonisolated enum TerminalOpeningBehavior: String, CaseIterable, Equatable, Sendable {
	case newWindow
	case newTab

	public var displayName: String {
		switch self {
		case .newWindow:
			"New Window"

		case .newTab:
			"New Tab"
		}
	}
}
