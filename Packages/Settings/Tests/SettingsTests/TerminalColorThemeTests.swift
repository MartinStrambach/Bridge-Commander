import Foundation
import Testing
@testable import Settings

@Suite("TerminalColorTheme")
struct TerminalColorThemeTests {
	@Test("displayName is human readable for every case")
	func displayNames() {
		#expect(TerminalColorTheme.basicDark.displayName == "Basic Dark")
		#expect(TerminalColorTheme.highContrast.displayName == "High Contrast")
		#expect(TerminalColorTheme.solarizedDark.displayName == "Solarized Dark")
		#expect(TerminalColorTheme.dracula.displayName == "Dracula")
		#expect(TerminalColorTheme.monokai.displayName == "Monokai")
		#expect(TerminalColorTheme.nord.displayName == "Nord")
		#expect(TerminalColorTheme.oneDark.displayName == "One Dark")
	}

	@Test("every case has a unique, non-empty display name")
	func displayNamesAreUnique() {
		let names = TerminalColorTheme.allCases.map(\.displayName)
		#expect(names.allSatisfy { !$0.isEmpty })
		#expect(Set(names).count == names.count)
	}

	@Test("round-trips through its raw value")
	func rawValueRoundTrip() {
		for theme in TerminalColorTheme.allCases {
			#expect(TerminalColorTheme(rawValue: theme.rawValue) == theme)
		}
	}

	@Test("foreground and background colors differ for every theme")
	func foregroundDiffersFromBackground() {
		for theme in TerminalColorTheme.allCases {
			#expect(theme.foregroundColor != theme.backgroundColor)
		}
	}

	@Test("exposes all seven themes")
	func allCasesCount() {
		#expect(TerminalColorTheme.allCases.count == 7)
	}
}
