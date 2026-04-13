public nonisolated enum TerminalApp: String, CaseIterable, Equatable, Sendable {
	case systemTerminal
	case iTerm2
	case ghostty
	case warp

	public var displayName: String {
		switch self {
		case .systemTerminal: "Terminal"
		case .iTerm2: "iTerm2"
		case .ghostty: "Ghostty"
		case .warp: "Warp"
		}
	}

	var appName: String {
		switch self {
		case .systemTerminal: "Terminal"
		case .iTerm2: "iTerm"
		case .ghostty: "Ghostty"
		case .warp: "Warp"
		}
	}

	public var supportsBehaviorSelection: Bool {
		switch self {
		case .systemTerminal, .iTerm2, .warp: true
		case .ghostty: false
		}
	}
}
