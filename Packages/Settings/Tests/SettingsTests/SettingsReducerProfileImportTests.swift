import ComposableArchitecture
import Foundation
import Testing
@testable import Settings

@MainActor
@Suite("SettingsReducer terminal profile import")
struct SettingsReducerProfileImportTests {
	private static func profile(_ name: String, ansi: [TerminalRGB]? = nil) -> TerminalProfile {
		TerminalProfile.fixture(name: name, ansi: ansi)
	}

	// MARK: - Importing from Terminal.app

	@Test("the Terminal.app button stores every profile it returns, sorted by name")
	func importsFromTerminalApp() async {
		let imported = [Self.profile("Ocean"), Self.profile("Basic")]
		let store = TestStore(initialState: SettingsReducer.State()) {
			SettingsReducer()
		} withDependencies: {
			$0[TerminalProfileImportClient.self].importFromTerminalApp = { imported }
		}

		await store.send(.importFromTerminalAppButtonTapped)
		await store.receive(\.profilesImported, imported) {
			$0.terminalProfiles = [Self.profile("Basic"), Self.profile("Ocean")]
			$0.alert = AlertState {
				TextState("Profiles Imported")
			} actions: {
				ButtonState(role: .cancel) { TextState("OK") }
			} message: {
				TextState(SettingsReducer.importSuccessMessage(imported))
			}
		}
	}

	@Test("a failure to read Terminal's settings is reported rather than silently ignored")
	func reportsTerminalAppFailure() async {
		let store = TestStore(initialState: SettingsReducer.State()) {
			SettingsReducer()
		} withDependencies: {
			$0[TerminalProfileImportClient.self].importFromTerminalApp = {
				throw TerminalProfileImportError.terminalPreferencesUnavailable
			}
		}

		await store.send(.importFromTerminalAppButtonTapped)
		await store.receive(
			\.profileImportFailed,
			TerminalProfileImportError.terminalPreferencesUnavailable.errorDescription!
		) {
			$0.alert = AlertState {
				TextState("Import Failed")
			} actions: {
				ButtonState(role: .cancel) { TextState("OK") }
			} message: {
				TextState(TerminalProfileImportError.terminalPreferencesUnavailable.errorDescription!)
			}
		}
		#expect(store.state.terminalProfiles.isEmpty)
	}

	// MARK: - Importing from files

	@Test("one unreadable file does not discard the profiles from the others")
	func partialFileFailureKeepsGoodProfiles() async {
		let good = Self.profile("Good")
		let store = TestStore(initialState: SettingsReducer.State()) {
			SettingsReducer()
		} withDependencies: {
			$0[TerminalProfileImportClient.self].importFromFile = { url in
				if url.lastPathComponent == "bad.terminal" {
					throw TerminalProfileImportError.notAPropertyList(name: "bad.terminal")
				}
				return [good]
			}
		}

		await store.send(.profileFilesSelected([
			URL(fileURLWithPath: "/tmp/bad.terminal"),
			URL(fileURLWithPath: "/tmp/good.terminal"),
		]))

		await store.receive(\.profilesImported, [good]) {
			$0.terminalProfiles = [good]
			$0.alert = AlertState {
				TextState("Profiles Imported")
			} actions: {
				ButtonState(role: .cancel) { TextState("OK") }
			} message: {
				TextState(SettingsReducer.importSuccessMessage([good]))
			}
		}
		await store.receive(
			\.profileImportFailed,
			TerminalProfileImportError.notAPropertyList(name: "bad.terminal").errorDescription!
		) {
			$0.alert = AlertState {
				TextState("Import Failed")
			} actions: {
				ButtonState(role: .cancel) { TextState("OK") }
			} message: {
				TextState(TerminalProfileImportError.notAPropertyList(name: "bad.terminal").errorDescription!)
			}
		}
	}

	// MARK: - Merging

	@Test("re-importing a profile updates it in place instead of duplicating the name")
	func reimportReplacesByName() {
		let existing = [Self.profile("Ocean"), Self.profile("Basic")]
		let updated = TerminalProfile(
			name: "Ocean",
			foreground: TerminalRGB(red: 1, green: 0, blue: 0),
			background: TerminalRGB(red: 0, green: 1, blue: 0)
		)

		let merged = SettingsReducer.merge([updated], into: existing)

		#expect(merged.map(\.name) == ["Basic", "Ocean"])
		#expect(merged.first { $0.name == "Ocean" } == updated)
	}

	@Test("merged profiles are sorted the way a person reads them")
	func mergeSortsNaturally() {
		let merged = SettingsReducer.merge(
			[Self.profile("Theme 10"), Self.profile("Theme 2")],
			into: [Self.profile("apple")]
		)

		// localizedStandardCompare: case-insensitive, and 2 before 10.
		#expect(merged.map(\.name) == ["apple", "Theme 2", "Theme 10"])
	}

	// MARK: - Deleting

	@Test("deleting the selected profile resets the terminal to a built-in theme")
	func deletingSelectedProfileResetsSelection() async {
		let store = TestStore(initialState: SettingsReducer.State()) {
			SettingsReducer()
		}
		await store.send(.profilesImported([Self.profile("Ocean")])) {
			$0.terminalProfiles = [Self.profile("Ocean")]
			$0.alert = AlertState {
				TextState("Profiles Imported")
			} actions: {
				ButtonState(role: .cancel) { TextState("OK") }
			} message: {
				TextState(SettingsReducer.importSuccessMessage([Self.profile("Ocean")]))
			}
		}
		await store.send(.setTerminalColorTheme(.imported(name: "Ocean"))) {
			$0.terminalColorTheme = .imported(name: "Ocean")
		}

		await store.send(.deleteProfileButtonTapped(name: "Ocean")) {
			$0.terminalProfiles = []
			$0.terminalColorTheme = .builtIn(.basicDark)
		}
	}

	@Test("deleting a profile that is not selected leaves the selection alone")
	func deletingOtherProfileKeepsSelection() async {
		let store = TestStore(initialState: SettingsReducer.State()) {
			SettingsReducer()
		}
		await store.send(.profilesImported([Self.profile("Ocean"), Self.profile("Grass")])) {
			$0.terminalProfiles = [Self.profile("Grass"), Self.profile("Ocean")]
			$0.alert = AlertState {
				TextState("Profiles Imported")
			} actions: {
				ButtonState(role: .cancel) { TextState("OK") }
			} message: {
				TextState(
					SettingsReducer.importSuccessMessage([Self.profile("Ocean"), Self.profile("Grass")])
				)
			}
		}
		await store.send(.setTerminalColorTheme(.imported(name: "Ocean"))) {
			$0.terminalColorTheme = .imported(name: "Ocean")
		}

		await store.send(.deleteProfileButtonTapped(name: "Grass")) {
			$0.terminalProfiles = [Self.profile("Ocean")]
		}
	}

	// MARK: - Messaging

	@Test("the success message calls out profiles that carry no ANSI palette")
	func successMessageMentionsMissingPalettes() {
		let complete = Self.profile("Ocean", ansi: TerminalProfile.fixtureAnsi())
		let bare = Self.profile("Basic")

		#expect(SettingsReducer.importSuccessMessage([complete]) == "Imported “Ocean”.")
		#expect(
			SettingsReducer.importSuccessMessage([bare])
				== "Imported “Basic”. “Basic” defines no ANSI colors, so the default palette is used for those."
		)

		let mixed = SettingsReducer.importSuccessMessage([complete, bare])
		#expect(mixed.hasPrefix("Imported 2 profiles."))
		#expect(mixed.contains("“Basic”"))
		#expect(!mixed.contains("“Ocean” defines"))
	}
}
