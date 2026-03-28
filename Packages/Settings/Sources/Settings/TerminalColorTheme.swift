import AppKit
import Foundation

public nonisolated enum TerminalColorTheme: String, CaseIterable, Equatable, Sendable {
	case basicDark
	case highContrast
	case solarizedDark
	case dracula
	case monokai
	case nord
	case oneDark

	public var displayName: String {
		switch self {
		case .basicDark: "Basic Dark"
		case .highContrast: "High Contrast"
		case .solarizedDark: "Solarized Dark"
		case .dracula: "Dracula"
		case .monokai: "Monokai"
		case .nord: "Nord"
		case .oneDark: "One Dark"
		}
	}

	public var foregroundColor: NSColor {
		switch self {
		case .basicDark: NSColor(red: 0.831, green: 0.831, blue: 0.831, alpha: 1) // #D4D4D4
		case .highContrast: .white
		case .solarizedDark: NSColor(red: 0.514, green: 0.580, blue: 0.588, alpha: 1) // #839496
		case .dracula: NSColor(red: 0.973, green: 0.973, blue: 0.949, alpha: 1) // #F8F8F2
		case .monokai: NSColor(red: 0.973, green: 0.973, blue: 0.973, alpha: 1) // #F8F8F8
		case .nord: NSColor(red: 0.847, green: 0.871, blue: 0.914, alpha: 1) // #D8DEE9
		case .oneDark: NSColor(red: 0.682, green: 0.710, blue: 0.780, alpha: 1) // #ABB2BF
		}
	}

	public var backgroundColor: NSColor {
		switch self {
		case .basicDark: NSColor(red: 0.118, green: 0.118, blue: 0.118, alpha: 1) // #1E1E1E
		case .highContrast: .black
		case .solarizedDark: NSColor(red: 0, green: 0.169, blue: 0.212, alpha: 1) // #002B36
		case .dracula: NSColor(red: 0.157, green: 0.165, blue: 0.212, alpha: 1) // #282A36
		case .monokai: NSColor(red: 0.153, green: 0.157, blue: 0.133, alpha: 1) // #272822
		case .nord: NSColor(red: 0.180, green: 0.204, blue: 0.251, alpha: 1) // #2E3440
		case .oneDark: NSColor(red: 0.157, green: 0.165, blue: 0.196, alpha: 1) // #282C34
		}
	}
}
