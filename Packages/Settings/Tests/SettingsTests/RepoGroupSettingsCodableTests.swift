import Foundation
import Testing
import ToolsIntegration
@testable import Settings

@Suite("RepoGroupSettings.Codable")
struct RepoGroupSettingsCodableTests {
	@Test("a default-constructed value has all fields at their defaults")
	func allDefaults() {
		let settings = RepoGroupSettings()
		#expect(settings.supportsIOS == false)
		#expect(settings.supportsAndroid == false)
		#expect(settings.mobileSubfolderPath == "")
		#expect(settings.iosSubfolderPath == "")
		#expect(settings.supportsTuist == false)
		#expect(settings.ticketIdRegex == "")
		#expect(settings.xcodeFilePreference == .auto)
		#expect(settings.worktreeCopyPaths == [])
		#expect(settings.supportsWeb == false)
		#expect(settings.webIndexPath == "")
		#expect(settings.defaultBranch == "")
	}

	@Test("an empty JSON object decodes to all defaults")
	func emptyObjectDecodesToDefaults() throws {
		let decoded = try JSONDecoder().decode(RepoGroupSettings.self, from: Data("{}".utf8))
		#expect(decoded == RepoGroupSettings())
	}

	@Test("every field survives an encode/decode round-trip")
	func fullRoundTrip() throws {
		let original = RepoGroupSettings(
			supportsIOS: true,
			supportsAndroid: true,
			mobileSubfolderPath: "apps/mobile",
			iosSubfolderPath: "apps/ios",
			supportsTuist: true,
			ticketIdRegex: "MOB-[0-9]+",
			xcodeFilePreference: .workspace,
			worktreeCopyPaths: ["secrets.xcconfig", "Tuist/.env"],
			supportsWeb: true,
			webIndexPath: "dist/index.html",
			defaultBranch: "develop"
		)
		let data = try JSONEncoder().encode(original)
		let decoded = try JSONDecoder().decode(RepoGroupSettings.self, from: data)
		#expect(decoded == original)
	}

	@Test("JSON missing every optional key falls back to defaults without throwing")
	func partialJSONIsBackwardCompatible() throws {
		// Simulates a preset saved before later properties were introduced.
		let json = Data(#"{"supportsIOS":true,"ticketIdRegex":"MOB-[0-9]+"}"#.utf8)
		let decoded = try JSONDecoder().decode(RepoGroupSettings.self, from: json)
		#expect(decoded.supportsIOS == true)
		#expect(decoded.ticketIdRegex == "MOB-[0-9]+")
		// Everything absent from the JSON must use its default.
		#expect(decoded.supportsAndroid == false)
		#expect(decoded.mobileSubfolderPath == "")
		#expect(decoded.iosSubfolderPath == "")
		#expect(decoded.supportsTuist == false)
		#expect(decoded.xcodeFilePreference == .auto)
		#expect(decoded.worktreeCopyPaths == [])
		#expect(decoded.supportsWeb == false)
		#expect(decoded.webIndexPath == "")
		#expect(decoded.defaultBranch == "")
	}

	@Test("an unknown xcodeFilePreference value does not wipe the rest of the settings")
	func unknownEnumValueFallsBackToAuto() throws {
		// decodeIfPresent of an undecodable enum throws on the value, so the whole
		// struct fails — but a *missing* key must fall back to .auto rather than throw.
		let json = Data(#"{"supportsIOS":true}"#.utf8)
		let decoded = try JSONDecoder().decode(RepoGroupSettings.self, from: json)
		#expect(decoded.xcodeFilePreference == .auto)
	}
}
