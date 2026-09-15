import AppKit
import Foundation
import Testing
@testable import Settings

/// Encodes what Terminal.app writes under a profile's `Font` key, so a test can name a face that
/// is not installed — archiving a real `NSFont` cannot, since one cannot be constructed.
/// Registered under the `NSFont` class name, so the archive is shaped exactly like Terminal's.
@objc(BCTestFontStub)
private final class FontStub: NSObject, NSCoding {
	let name: String
	let size: Double

	init(name: String, size: Double) {
		self.name = name
		self.size = size
	}

	init?(coder: NSCoder) { return nil }

	func encode(with coder: NSCoder) {
		coder.encode(name as NSString, forKey: "NSName")
		coder.encode(size, forKey: "NSSize")
		coder.encode(16, forKey: "NSfFlags")
	}
}

@Suite("TerminalProfileImporter")
struct TerminalProfileImporterTests {

	// MARK: - Helpers

	/// Encodes a color the way Terminal.app stores one: an `NSKeyedArchiver` blob, not a string.
	static func archived(_ color: NSColor) -> Data {
		try! NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: true)
	}

	/// Encodes a font the way Terminal.app stores one, for any face name — including one that is
	/// not installed, which is the case the importer exists to survive and which real
	/// `NSKeyedArchiver.archivedData(withRootObject: NSFont…)` cannot produce.
	static func archivedFont(name: String, size: Double) -> Data {
		let archiver = NSKeyedArchiver(requiringSecureCoding: false)
		archiver.setClassName("NSFont", for: FontStub.self)
		archiver.encode(FontStub(name: name, size: size), forKey: NSKeyedArchiveRootObjectKey)
		archiver.finishEncoding()
		return archiver.encodedData
	}

	static func profileDictionary(
		name: String = "Test Profile",
		includeAnsi: Bool = true,
		ansiCount: Int = TerminalProfile.ansiColorCount
	) -> [String: Any] {
		var dict: [String: Any] = [
			"name": name,
			"type": "Window Settings",
			"BackgroundColor": archived(NSColor(srgbRed: 0.1, green: 0.2, blue: 0.3, alpha: 1)),
			"TextColor": archived(NSColor(srgbRed: 0.9, green: 0.9, blue: 0.9, alpha: 1)),
		]
		if includeAnsi {
			for (index, key) in TerminalProfileImporter.ansiColorKeys.prefix(ansiCount).enumerated() {
				dict[key] = archived(
					NSColor(srgbRed: Double(index) / 16, green: 0.5, blue: 0.25, alpha: 1)
				)
			}
		}
		return dict
	}

	// MARK: - Exported file shape

	@Test("an exported profile dictionary is imported with its colors")
	func importsSingleProfile() {
		let profiles = TerminalProfileImporter.profiles(fromPropertyList: Self.profileDictionary())

		#expect(profiles.count == 1)
		let profile = try! #require(profiles.first)
		#expect(profile.name == "Test Profile")
		#expect(profile.background == TerminalRGB(red: 0.1, green: 0.2, blue: 0.3))
		#expect(profile.foreground == TerminalRGB(red: 0.9, green: 0.9, blue: 0.9))
		#expect(profile.ansi?.count == 16)
	}

	@Test("the ANSI palette keeps Terminal's key order: eight normal colors, then eight bright")
	func ansiKeyOrder() {
		#expect(TerminalProfileImporter.ansiColorKeys.count == TerminalProfile.ansiColorCount)
		#expect(TerminalProfileImporter.ansiColorKeys.first == "ANSIBlackColor")
		#expect(TerminalProfileImporter.ansiColorKeys[7] == "ANSIWhiteColor")
		#expect(TerminalProfileImporter.ansiColorKeys[8] == "ANSIBrightBlackColor")
		#expect(TerminalProfileImporter.ansiColorKeys.last == "ANSIBrightWhiteColor")
	}

	@Test("a profile without a name falls back to the file name")
	func fallsBackToFileName() {
		var dict = Self.profileDictionary()
		dict.removeValue(forKey: "name")

		let profiles = TerminalProfileImporter.profiles(
			fromPropertyList: dict,
			fallbackName: "Solarized"
		)

		#expect(profiles.first?.name == "Solarized")
	}

	// MARK: - Partial profiles

	@Test("a profile defining no ANSI colors imports with no palette, not a broken one")
	func noAnsiColors() {
		let profiles = TerminalProfileImporter.profiles(
			fromPropertyList: Self.profileDictionary(includeAnsi: false)
		)

		#expect(profiles.first?.ansi == nil)
	}

	@Test("a partial ANSI palette is discarded rather than half-applied")
	func partialAnsiPalette() {
		// SwiftTerm ignores any array that is not exactly 16 long, so 15 colors would leave
		// the previous theme's palette installed and read as a rendering bug.
		let profiles = TerminalProfileImporter.profiles(
			fromPropertyList: Self.profileDictionary(ansiCount: 15)
		)

		#expect(profiles.first?.ansi == nil)
	}

	@Test("a profile setting neither text nor background color uses Terminal's black-on-white")
	func defaultsForMissingColors() {
		// This is Apple's bundled "Basic" profile: it defines a font and nothing else.
		let dict: [String: Any] = ["name": "Basic", "type": "Window Settings"]

		let profile = try! #require(TerminalProfileImporter.profiles(fromPropertyList: dict).first)
		#expect(profile.foreground == TerminalRGB(red: 0, green: 0, blue: 0))
		#expect(profile.background == TerminalRGB(red: 1, green: 1, blue: 1))
	}

	// MARK: - Color decoding

	@Test("a grayscale color is converted instead of raising on a missing RGB component")
	func decodesGrayscaleColor() {
		// Apple's "Pro" profile stores its background in Generic Gray.
		var dict = Self.profileDictionary()
		dict["BackgroundColor"] = Self.archived(NSColor(white: 0, alpha: 1))

		let profile = try! #require(TerminalProfileImporter.profiles(fromPropertyList: dict).first)
		#expect(profile.background == TerminalRGB(red: 0, green: 0, blue: 0))
	}

	@Test("translucency is dropped, because the built-in terminal has none")
	func dropsAlpha() {
		// Terminal's "Clear" profiles store alpha 0.85–0.95.
		var dict = Self.profileDictionary()
		dict["BackgroundColor"] = Self.archived(
			NSColor(srgbRed: 0.1, green: 0.2, blue: 0.3, alpha: 0.5)
		)

		let profile = try! #require(TerminalProfileImporter.profiles(fromPropertyList: dict).first)
		#expect(profile.background == TerminalRGB(red: 0.1, green: 0.2, blue: 0.3))
		#expect(profile.background.nsColor.alphaComponent == 1)
	}

	@Test("a color in a non-sRGB space is converted, not read raw")
	func convertsColorSpace() {
		var dict = Self.profileDictionary()
		let generic = NSColor(calibratedRed: 0.5, green: 0.5, blue: 0.5, alpha: 1)
		dict["BackgroundColor"] = Self.archived(generic)

		let profile = try! #require(TerminalProfileImporter.profiles(fromPropertyList: dict).first)
		let expected = try! #require(TerminalRGB(generic))
		#expect(profile.background == expected)
	}

	@Test("a value that is not an archived color is ignored")
	func ignoresNonColorValues() {
		var dict = Self.profileDictionary()
		dict["BackgroundColor"] = "#FF0000"

		let profile = try! #require(TerminalProfileImporter.profiles(fromPropertyList: dict).first)
		// Falls back to the default rather than importing garbage.
		#expect(profile.background == TerminalRGB(red: 1, green: 1, blue: 1))
	}

	// MARK: - Font decoding

	@Test("a profile's font is imported with its name and size")
	func decodesFont() {
		var dict = Self.profileDictionary()
		dict["Font"] = Self.archivedFont(name: "Menlo-Regular", size: 14)

		let profile = try! #require(TerminalProfileImporter.profiles(fromPropertyList: dict).first)
		#expect(profile.font == TerminalProfileFont(name: "Menlo-Regular", size: 14))
	}

	@Test("an archive written by AppKit itself decodes the same way")
	func decodesRealAppKitArchive() throws {
		// The stub encoder above has to match what Terminal writes; a genuine NSFont archive is
		// the check that it does.
		let font = try #require(NSFont(name: "Menlo-Regular", size: 15))
		var dict = Self.profileDictionary()
		dict["Font"] = try NSKeyedArchiver.archivedData(
			withRootObject: font,
			requiringSecureCoding: true
		)

		let profile = try #require(TerminalProfileImporter.profiles(fromPropertyList: dict).first)
		#expect(profile.font == TerminalProfileFont(name: "Menlo-Regular", size: 15))
	}

	@Test("a font that is not installed keeps its own name instead of AppKit's substitute")
	func keepsUnavailableFontName() {
		// Terminal's own profiles name SFMonoTerminal-Regular, which ships inside Terminal.app
		// and is not registered system-wide. Decoding the archive as an NSFont would substitute
		// .AppleSystemUIFont — a proportional face — and record that instead.
		var dict = Self.profileDictionary()
		dict["Font"] = Self.archivedFont(name: "SFMonoTerminal-Regular", size: 12)

		let font = try! #require(TerminalProfileImporter.profiles(fromPropertyList: dict).first?.font)
		#expect(font.name == "SFMonoTerminal-Regular")
		#expect(font.size == 12)
	}

	@Test("a profile that defines no font imports without one")
	func noFont() {
		let profile = try! #require(TerminalProfileImporter.profiles(fromPropertyList: Self.profileDictionary()).first)
		#expect(profile.font == nil)
	}

	@Test("a Font value that is not an archived font is ignored")
	func ignoresNonFontValues() {
		var dict = Self.profileDictionary()
		dict["Font"] = "Menlo 12"

		#expect(TerminalProfileImporter.profiles(fromPropertyList: dict).first?.font == nil)

		dict["Font"] = Self.archived(NSColor.red)
		#expect(TerminalProfileImporter.profiles(fromPropertyList: dict).first?.font == nil)
	}

	@Test("a font size outside the supported range is clamped, not stored raw")
	func clampsFontSize() {
		var dict = Self.profileDictionary()
		dict["Font"] = Self.archivedFont(name: "Menlo-Regular", size: 96)

		let font = try! #require(TerminalProfileImporter.profiles(fromPropertyList: dict).first?.font)
		#expect(font.size == TerminalFontSize.maximum)
	}

	// MARK: - Preferences shape

	@Test("Terminal's preferences domain yields every profile, sorted by name")
	func importsWindowSettingsDomain() {
		let domain: [String: Any] = [
			"Window Settings": [
				"Ocean": Self.profileDictionary(name: "Ocean"),
				"Basic": Self.profileDictionary(name: "Basic"),
				"pro": Self.profileDictionary(name: "pro"),
			],
			"Default Window Settings": "Basic",
		]

		let profiles = TerminalProfileImporter.profiles(fromPropertyList: domain)

		#expect(profiles.map(\.name) == ["Basic", "Ocean", "pro"])
	}

	// MARK: - Rejecting non-profiles

	@Test("an unrelated property list imports nothing rather than a default-built theme")
	func rejectsUnrelatedPropertyList() {
		#expect(TerminalProfileImporter.profiles(fromPropertyList: ["Foo": "Bar"]).isEmpty)
		#expect(TerminalProfileImporter.profiles(fromPropertyList: [1, 2, 3]).isEmpty)
		#expect(TerminalProfileImporter.profiles(fromPropertyList: "not a dictionary").isEmpty)
	}

	@Test("a dictionary with colors but no type is still recognized as a profile")
	func acceptsProfileWithoutTypeKey() {
		var dict = Self.profileDictionary(name: "Colors Only")
		dict.removeValue(forKey: "type")

		#expect(TerminalProfileImporter.profiles(fromPropertyList: dict).count == 1)
	}

	// MARK: - Files

	@Test("reading a file that is not a property list reports it as such")
	func rejectsNonPropertyListFile() throws {
		let url = URL(fileURLWithPath: NSTemporaryDirectory())
			.appending(component: "bogus-\(UUID().uuidString).terminal")
		try Data("definitely not a plist".utf8).write(to: url)
		defer { try? FileManager.default.removeItem(at: url) }

		#expect(throws: TerminalProfileImportError.notAPropertyList(name: url.lastPathComponent)) {
			try TerminalProfileImporter.profiles(fromFileAt: url)
		}
	}

	@Test("reading a missing file reports it as unreadable")
	func rejectsMissingFile() {
		let url = URL(fileURLWithPath: "/nonexistent/Nope.terminal")

		#expect(throws: TerminalProfileImportError.unreadableFile(name: "Nope.terminal")) {
			try TerminalProfileImporter.profiles(fromFileAt: url)
		}
	}

	@Test("a valid exported file round-trips")
	func readsExportedFile() throws {
		let url = URL(fileURLWithPath: NSTemporaryDirectory())
			.appending(component: "Exported-\(UUID().uuidString).terminal")
		let data = try PropertyListSerialization.data(
			fromPropertyList: Self.profileDictionary(name: "Exported"),
			format: .xml,
			options: 0
		)
		try data.write(to: url)
		defer { try? FileManager.default.removeItem(at: url) }

		let profiles = try TerminalProfileImporter.profiles(fromFileAt: url)

		#expect(profiles.map(\.name) == ["Exported"])
		#expect(profiles.first?.ansi?.count == 16)
	}

	@Test("a property list holding no profile reports that, rather than importing nothing quietly")
	func reportsFileWithoutProfiles() throws {
		let url = URL(fileURLWithPath: NSTemporaryDirectory())
			.appending(component: "Empty-\(UUID().uuidString).terminal")
		let data = try PropertyListSerialization.data(
			fromPropertyList: ["Unrelated": "Value"],
			format: .xml,
			options: 0
		)
		try data.write(to: url)
		defer { try? FileManager.default.removeItem(at: url) }

		#expect(throws: TerminalProfileImportError.noProfilesFound(name: url.lastPathComponent)) {
			try TerminalProfileImporter.profiles(fromFileAt: url)
		}
	}
}

@Suite("TerminalProfile")
struct TerminalProfileTests {
	@Test("a palette that is not exactly 16 colors is rejected at construction")
	func rejectsWrongPaletteLength() {
		for count in [0, 1, 8, 15, 17] {
			let profile = TerminalProfile.fixture(name: "P", ansi: TerminalProfile.fixtureAnsi(count: count))
			#expect(profile.ansi == nil, "expected \(count) colors to be rejected")
		}
		#expect(TerminalProfile.fixture(name: "P", ansi: TerminalProfile.fixtureAnsi()).ansi?.count == 16)
	}

	@Test("a short palette in stored JSON is rejected on decode too")
	func rejectsWrongPaletteLengthWhenDecoding() throws {
		let short = TerminalProfile.fixtureAnsi(count: 3)
		let json = """
		{
			"name": "Hand edited",
			"foreground": {"red": 1, "green": 1, "blue": 1},
			"background": {"red": 0, "green": 0, "blue": 0},
			"ansi": \(String(data: try JSONEncoder().encode(short), encoding: .utf8)!)
		}
		"""

		let decoded = try JSONDecoder().decode(TerminalProfile.self, from: Data(json.utf8))

		#expect(decoded.ansi == nil)
		#expect(decoded.name == "Hand edited")
	}

	@Test("round-trips through JSON, which is how profiles are persisted")
	func codableRoundTrip() throws {
		var profile = TerminalProfile.fixture(name: "Ocean", ansi: TerminalProfile.fixtureAnsi())
		profile.font = TerminalProfileFont(name: "Menlo-Regular", size: 14)
		let data = try JSONEncoder().encode(profile)

		#expect(try JSONDecoder().decode(TerminalProfile.self, from: data) == profile)
	}

	@Test("a profile stored before fonts were imported still decodes")
	func decodesWithoutFont() throws {
		let json = """
		{
			"name": "Ocean",
			"foreground": {"red": 1, "green": 1, "blue": 1},
			"background": {"red": 0, "green": 0, "blue": 0}
		}
		"""

		#expect(try JSONDecoder().decode(TerminalProfile.self, from: Data(json.utf8)).font == nil)
	}

	@Test("a font size is clamped to the range the setting supports")
	func clampsFontSize() {
		#expect(TerminalProfileFont(name: "Menlo", size: 96).size == TerminalFontSize.maximum)
		#expect(TerminalProfileFont(name: "Menlo", size: 0).size == TerminalFontSize.minimum)
	}

	@Test("availability follows whether the face can actually be loaded")
	func fontAvailability() {
		#expect(TerminalProfileFont(name: "Menlo-Regular", size: 12).isAvailable)
		// Ships inside Terminal.app, not registered system-wide.
		#expect(!TerminalProfileFont(name: "SFMonoTerminal-Regular", size: 12).isAvailable)
		#expect(!TerminalProfileFont(name: "", size: 12).isAvailable)
	}

	@Test("out-of-range components are clamped rather than producing an invalid color")
	func clampsComponents() {
		#expect(TerminalRGB(red: 2, green: -1, blue: 0.5) == TerminalRGB(red: 1, green: 0, blue: 0.5))
		#expect(TerminalRGB(red: .nan, green: 0, blue: 0).red == 0)
	}

	@Test("converts to and from NSColor without drift")
	func nsColorRoundTrip() throws {
		let original = TerminalRGB(red: 0.25, green: 0.5, blue: 0.75)
		let converted = try #require(TerminalRGB(original.nsColor))

		#expect(abs(converted.red - original.red) < 0.0001)
		#expect(abs(converted.green - original.green) < 0.0001)
		#expect(abs(converted.blue - original.blue) < 0.0001)
	}
}
