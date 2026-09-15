import Foundation
import Testing
@testable import Settings

@Suite("TerminalThemeSelection")
struct TerminalThemeSelectionTests {
	@Test("round-trips through its raw value")
	func rawValueRoundTrip() {
		let selections = TerminalColorTheme.allCases.map(TerminalThemeSelection.builtIn)
			+ [.imported(name: "Solarized Dark"), .imported(name: "My: weird name")]

		for selection in selections {
			#expect(TerminalThemeSelection(rawValue: selection.rawValue) == selection)
		}
	}

	@Test("a built-in theme's raw value stays the bare theme name, so old settings migrate")
	func builtInRawValueIsUnprefixed() {
		#expect(TerminalThemeSelection.builtIn(.dracula).rawValue == "dracula")
		// What a user who picked Dracula before profiles existed has in user defaults.
		#expect(TerminalThemeSelection(rawValue: "dracula") == .builtIn(.dracula))
	}

	@Test("an unknown raw value is rejected rather than silently imported")
	func unknownRawValue() {
		#expect(TerminalThemeSelection(rawValue: "nonsense") == nil)
		#expect(TerminalThemeSelection(rawValue: "") == nil)
		// An imported profile must have a name.
		#expect(TerminalThemeSelection(rawValue: "imported:") == nil)
	}

	@Test("a built-in selection resolves to the theme's colors and no palette")
	func resolvesBuiltIn() {
		let resolved = TerminalThemeSelection.builtIn(.nord).resolve(profiles: [])

		#expect(resolved.foreground == TerminalColorTheme.nord.foregroundColor)
		#expect(resolved.background == TerminalColorTheme.nord.backgroundColor)
		#expect(resolved.ansiPalette == nil)
	}

	@Test("an imported selection resolves to the profile's colors and palette")
	func resolvesImported() {
		let profile = TerminalProfile.fixture(name: "Ocean", ansi: TerminalProfile.fixtureAnsi())
		let resolved = TerminalThemeSelection.imported(name: "Ocean").resolve(profiles: [profile])

		#expect(TerminalRGB(resolved.foreground) == profile.foreground)
		#expect(TerminalRGB(resolved.background) == profile.background)
		#expect(resolved.ansiPalette?.count == 16)
	}

	@Test("a profile without ANSI colors resolves to no palette, keeping the default one")
	func resolvesImportedWithoutPalette() {
		let profile = TerminalProfile.fixture(name: "Ocean", ansi: nil)
		let resolved = TerminalThemeSelection.imported(name: "Ocean").resolve(profiles: [profile])

		#expect(resolved.ansiPalette == nil)
		#expect(TerminalRGB(resolved.background) == profile.background)
	}

	@Test("a selection naming a deleted profile falls back to the default theme")
	func resolvesMissingProfile() {
		let resolved = TerminalThemeSelection.imported(name: "Gone").resolve(profiles: [])

		#expect(resolved.foreground == TerminalColorTheme.basicDark.foregroundColor)
		#expect(resolved.background == TerminalColorTheme.basicDark.backgroundColor)
		#expect(resolved.ansiPalette == nil)
	}
}

// MARK: - Fixtures

extension TerminalProfile {
	static func fixture(name: String, ansi: [TerminalRGB]? = nil) -> TerminalProfile {
		TerminalProfile(
			name: name,
			foreground: TerminalRGB(red: 0.8, green: 0.8, blue: 0.8),
			background: TerminalRGB(red: 0.1, green: 0.1, blue: 0.2),
			ansi: ansi
		)
	}

	static func fixtureAnsi(count: Int = TerminalProfile.ansiColorCount) -> [TerminalRGB] {
		(0 ..< count).map { index in
			TerminalRGB(red: Double(index) / 16, green: 0.5, blue: 0.25)
		}
	}
}
