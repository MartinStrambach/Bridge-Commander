import AppKit
import Testing

@testable import Settings

@Suite("TerminalFontFamily")
struct TerminalFontFamilyTests {

	@Test("The sentinel resolves to the system monospaced face at the requested size")
	func systemDefaultResolves() {
		let font = TerminalFontFamily.resolve(name: TerminalFontFamily.systemDefault, size: 17)
		#expect(font.pointSize == 17)
		#expect(font == NSFont.monospacedSystemFont(ofSize: 17, weight: .regular))
	}

	@Test("A named font resolves to that font")
	func namedFontResolves() {
		let font = TerminalFontFamily.resolve(name: "Menlo", size: 14)
		#expect(font.familyName == "Menlo")
		#expect(font.pointSize == 14)
	}

	@Test("An uninstallable name falls back rather than failing")
	func unknownFontFallsBack() {
		let font = TerminalFontFamily.resolve(name: "Not A Real Font 12345", size: 14)
		#expect(font == NSFont.monospacedSystemFont(ofSize: 14, weight: .regular))
	}

	@Test("The size is clamped, since it comes from the same defaults the font name does")
	func sizeIsClamped() {
		#expect(
			Double(TerminalFontFamily.resolve(name: "Menlo", size: 0).pointSize)
				== TerminalFontSize.minimum
		)
		#expect(
			Double(TerminalFontFamily.resolve(name: "", size: 999).pointSize)
				== TerminalFontSize.maximum
		)
	}

	@Test("Availability covers the sentinel and rejects unknown names")
	func availability() {
		#expect(TerminalFontFamily.isAvailable(name: TerminalFontFamily.systemDefault))
		#expect(TerminalFontFamily.isAvailable(name: "Menlo"))
		#expect(!TerminalFontFamily.isAvailable(name: "Not A Real Font 12345"))
	}

	@Test("The listed families are monospaced and include the ones macOS always ships")
	func monospacedFamilies() {
		let families = TerminalFontFamily.availableMonospacedFamilies()
		#expect(families.contains("Menlo"))
		#expect(!families.contains("Helvetica"))
		#expect(families == families.sorted())
	}

	@Test("Only the sentinel gets a substituted label")
	func displayName() {
		#expect(
			TerminalFontFamily.displayName(for: TerminalFontFamily.systemDefault)
				== TerminalFontFamily.systemDefaultDisplayName
		)
		#expect(TerminalFontFamily.displayName(for: "Menlo") == "Menlo")
	}
}
