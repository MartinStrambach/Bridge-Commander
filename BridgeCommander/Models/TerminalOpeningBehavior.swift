import Foundation

nonisolated enum TerminalOpeningBehavior: String, CaseIterable, Equatable, Sendable {
	case newWindow
	case newTab

	var displayName: String {
		switch self {
		case .newWindow:
			"New Window"

		case .newTab:
			"New Tab"
		}
	}
}
